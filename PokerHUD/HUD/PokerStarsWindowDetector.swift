import AppKit

/// Detects PokerStars table windows and their positions using CGWindowList API
struct PokerStarsWindowDetector {

    /// Find all PokerStars table windows and return their frames
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

        return results
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

    /// Prompt user to grant Screen Recording permission
    @discardableResult
    static func requestScreenRecordingPermission() -> CGImage? {
        CGWindowListCreateImage(
            CGRect(x: 0, y: 0, width: 1, height: 1),
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        )
    }
}

struct DetectedPokerWindow {
    let windowID: CGWindowID
    let windowName: String
    let frame: NSRect
    let ownerName: String
}
