import AppKit

/// Detects PokerStars table windows and their positions using CGWindowList API
struct PokerStarsWindowDetector {

    /// Find all PokerStars table windows and return their frames.
    ///
    /// Phase 2 enrichment: when CGWindowList cannot populate `windowName`
    /// (because Screen Recording permission is not granted), this method
    /// falls back to `AccessibilityWindowReader` — which reads titles via
    /// the Accessibility API instead — and merges any matched titles into
    /// the result. The merge is by frame match (the two APIs report the
    /// same geometry for the same on-screen window). This is what makes
    /// `HUDManager.findWindowFrame`'s name-based binding path reachable on
    /// machines that only granted Accessibility, not Screen Recording, and
    /// is the root fix for the brittle multi-table binding that has dogged
    /// prior Phase 2 attempts (see commits `3534c8b`, `cf705c0`).
    static func findTableWindows() -> [DetectedPokerWindow] {
        var results: [DetectedPokerWindow] = []

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return results
        }

        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  ownerName.lowercased().contains("pokerstars") else {
                continue
            }

            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat else {
                continue
            }

            // kCGWindowName requires Screen Recording permission on macOS 10.15+
            // If nil, the app doesn't have permission — we handle this gracefully
            let windowName = window[kCGWindowName as String] as? String ?? ""

            guard let windowID = window[kCGWindowNumber as String] as? CGWindowID else { continue }

            // Skip our own HUD panels
            guard !ownerName.contains("PokerHUD") else { continue }

            // Filter for table windows (minimum size — tables are typically 800+ x 500+)
            guard width > 600 && height > 400 else { continue }

            // Convert from CGWindow coordinates (top-left origin) to NSScreen (bottom-left origin)
            let screenHeight = NSScreen.main?.frame.height ?? 900
            let flippedY = screenHeight - y - height

            let frame = NSRect(x: x, y: flippedY, width: width, height: height)
            results.append(DetectedPokerWindow(
                windowID: windowID,
                windowName: windowName,
                frame: frame,
                ownerName: ownerName
            ))
        }

        return enrichWithAXTitles(results).filter { !isLobbyLikeWindow($0) }
    }

    /// Returns true if the detected window looks like a PokerStars non-table
    /// window (currently just the main Lobby and tournament/SNG lobbies)
    /// that must be excluded from the HUD binding candidate list.
    ///
    /// Without this filter the Lobby window (~1280×768 on macOS) passes the
    /// 600×400 size floor and becomes eligible for the exclusion fallback in
    /// `HUDManager.findWindowFrame` / `AppState.autoManageTables`, which
    /// then happily binds a real DB table to it and renders HUD panels on
    /// top of the lobby. The user reported exactly this symptom with a
    /// screenshot showing 5 player panels rendered over "PokerStars Lobby -
    /// Last Login: …".
    ///
    /// Implementation: substring match on "Lobby" (case-insensitive). The
    /// PokerStars macOS lobby title is always of the form "PokerStars
    /// Lobby - Last Login: <timestamp>" regardless of the client's locale
    /// (verified against the Italian client). Real cash-game table names
    /// are never composed with the word "Lobby" — they're things like
    /// "Fidelio V", "Aruna V", "Celbalrai V" — so the false-positive risk
    /// is effectively zero.
    ///
    /// Title-less fallback: when neither Screen Recording nor Accessibility
    /// is granted, `windowName` is empty and we can't distinguish the lobby
    /// from a table without resorting to brittle size heuristics. In that
    /// case we keep the window (pre-PR status quo) and rely on the user
    /// having granted at least one permission. The `[HUD][diag]` log
    /// already prints `axGranted=false` + `<no-title>` when this happens,
    /// so the diagnostic trail exists.
    private static func isLobbyLikeWindow(_ window: DetectedPokerWindow) -> Bool {
        guard !window.windowName.isEmpty else { return false }
        if window.windowName.localizedCaseInsensitiveContains("Lobby") {
            print("[HUD] Excluding lobby window \(window.windowID): '\(window.windowName.prefix(60))'")
            return true
        }
        return false
    }

    /// If any of the detected windows have an empty `windowName` — which
    /// happens when Screen Recording is denied — ask AX for PokerStars
    /// window titles and fill them in by frame match.
    ///
    /// Matching is by position/size with a 2-point tolerance to absorb
    /// sub-pixel rounding between the two APIs. CGWindowList is still the
    /// source of identity (`CGWindowID`), so nothing about the existing
    /// binding map in `HUDManager` has to change.
    private static func enrichWithAXTitles(_ cgWindows: [DetectedPokerWindow]) -> [DetectedPokerWindow] {
        guard cgWindows.contains(where: { $0.windowName.isEmpty }) else { return cgWindows }
        let axWindows = AccessibilityWindowReader.findPokerStarsWindows()
        guard !axWindows.isEmpty else { return cgWindows }

        return cgWindows.map { cgWindow in
            guard cgWindow.windowName.isEmpty else { return cgWindow }
            guard let match = axWindows.first(where: { framesMatch($0.frame, cgWindow.frame) }) else {
                return cgWindow
            }
            return DetectedPokerWindow(
                windowID: cgWindow.windowID,
                windowName: match.title,
                frame: cgWindow.frame,
                ownerName: cgWindow.ownerName
            )
        }
    }

    /// Tolerant frame equality for matching AX windows to CGWindowList
    /// windows. 2 points is comfortably below any real window move and
    /// above any rounding difference between the two APIs.
    private static func framesMatch(_ a: NSRect, _ b: NSRect) -> Bool {
        abs(a.origin.x - b.origin.x) < 2
            && abs(a.origin.y - b.origin.y) < 2
            && abs(a.width - b.width) < 2
            && abs(a.height - b.height) < 2
    }

    /// Calculate HUD panel positions relative to a PokerStars table window.
    /// PokerStars always places the hero at bottom-center, then arranges other players
    /// clockwise around the table relative to the hero.
    ///
    /// - Parameters:
    ///   - windowFrame: The PokerStars window frame
    ///   - tableSize: Max seats (6 or 9)
    ///   - heroSeat: The hero's seat number
    ///   - occupiedSeats: All occupied seat numbers
    static func seatPositions(
        for windowFrame: NSRect,
        tableSize: Int,
        heroSeat: Int,
        occupiedSeats: [Int]
    ) -> [Int: CGPoint] {
        let w = windowFrame.width
        let h = windowFrame.height
        let x = windowFrame.origin.x
        let y = windowFrame.origin.y

        // Visual positions around the table (bottom-center is index 0, going clockwise)
        // macOS coordinate system: Y=0 at bottom of screen, Y increases upward
        // So top of window = y + h, bottom of window = y
        // "top" on table = high Y, "bottom" on table = low Y
        let top = y + h    // top of window
        let bot = y        // bottom of window

        let visualSlots6: [CGPoint] = [
            CGPoint(x: x + w * 0.42, y: bot + h * 0.12),  // 0: Bottom-center (HERO)
            CGPoint(x: x + w * 0.02, y: bot + h * 0.30),  // 1: Bottom-left
            CGPoint(x: x + w * 0.05, y: top - h * 0.35),  // 2: Top-left
            CGPoint(x: x + w * 0.38, y: top - h * 0.18),  // 3: Top-center
            CGPoint(x: x + w * 0.70, y: top - h * 0.35),  // 4: Top-right
            CGPoint(x: x + w * 0.70, y: bot + h * 0.30),  // 5: Bottom-right
        ]

        let visualSlots9: [CGPoint] = [
            CGPoint(x: x + w * 0.42, y: bot + h * 0.10),  // 0: Bottom-center (HERO)
            CGPoint(x: x + w * 0.02, y: bot + h * 0.22),  // 1: Bottom-left
            CGPoint(x: x + w * 0.02, y: bot + h * 0.42),  // 2: Left
            CGPoint(x: x + w * 0.08, y: top - h * 0.30),  // 3: Top-left
            CGPoint(x: x + w * 0.32, y: top - h * 0.18),  // 4: Top-center-left
            CGPoint(x: x + w * 0.55, y: top - h * 0.18),  // 5: Top-center-right
            CGPoint(x: x + w * 0.72, y: top - h * 0.30),  // 6: Top-right
            CGPoint(x: x + w * 0.78, y: bot + h * 0.42),  // 7: Right
            CGPoint(x: x + w * 0.70, y: bot + h * 0.22),  // 8: Bottom-right
        ]

        let slots = tableSize <= 6 ? visualSlots6 : visualSlots9
        let maxSeats = tableSize <= 6 ? 6 : 9

        // Map seat numbers to visual positions
        // PokerStars arranges seats clockwise: hero is always at visual slot 0,
        // then seats go clockwise from hero's left
        var result: [Int: CGPoint] = [:]

        for seatNumber in occupiedSeats {
            // Calculate how many positions clockwise this seat is from hero
            let offset = (seatNumber - heroSeat + maxSeats) % maxSeats
            if offset < slots.count {
                result[seatNumber] = slots[offset]
            }
        }

        return result
    }
}

extension PokerStarsWindowDetector {
    /// Check if we can read window names (Screen Recording permission)
    /// Only checks PokerStars windows specifically — system windows always have names
    static func hasScreenRecordingPermission() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        // Check specifically if PokerStars windows have readable names
        let pokerWindows = windowList.filter {
            let owner = $0[kCGWindowOwnerName as String] as? String ?? ""
            return owner.lowercased().contains("pokerstars")
        }
        // If no PokerStars windows, we can't tell — assume no permission
        guard !pokerWindows.isEmpty else { return false }
        // If ANY PokerStars window has a name, we have permission
        return pokerWindows.contains { w in
            let name = w[kCGWindowName as String] as? String
            return name != nil && !name!.isEmpty
        }
    }

    /// Prompt the user to grant Screen Recording permission. Returns true
    /// if permission is already granted (no prompt is shown). On the first
    /// call when not yet granted, macOS shows the standard "Allow Screen
    /// Recording" dialog and returns false; the user then has to act in
    /// System Settings, so a relaunch is required to pick up the change.
    ///
    /// Replaces the previous `CGWindowListCreateImage(1×1)` side-effect
    /// trick, which was deprecated in macOS 14. `CGRequestScreenCaptureAccess`
    /// is the canonical modern API for triggering this prompt and is
    /// available since macOS 11 — well below our deployment target.
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

struct DetectedPokerWindow {
    let windowID: CGWindowID
    let windowName: String
    let frame: NSRect
    let ownerName: String
}
