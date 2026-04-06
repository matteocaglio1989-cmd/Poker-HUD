import AppKit

/// Detects PokerStars table windows using AppleScript (reads window titles reliably)
/// and CGWindowList (reads window frames accurately)
struct PokerStarsWindowDetector {

    /// Find all PokerStars table windows with their titles and positions
    static func findTableWindows() -> [DetectedPokerWindow] {
        // Use AppleScript to get window names + positions (reliable for titles)
        let appleScriptWindows = getWindowsViaAppleScript()
        if !appleScriptWindows.isEmpty {
            return appleScriptWindows
        }

        // Fallback to CGWindowList if AppleScript fails
        return getWindowsViaCGWindowList()
    }

    // MARK: - AppleScript approach (reliable window titles)

    private static func getWindowsViaAppleScript() -> [DetectedPokerWindow] {
        // Get window names
        let nameScript = NSAppleScript(source: """
            tell application "System Events" to tell process "PokerStars"
                set windowNames to name of every window
                set output to ""
                repeat with n in windowNames
                    set output to output & n & "|||"
                end repeat
                return output
            end tell
        """)

        // Get window positions
        let posScript = NSAppleScript(source: """
            tell application "System Events" to tell process "PokerStars"
                set output to ""
                repeat with w in every window
                    set {x, y} to position of w
                    set {ww, hh} to size of w
                    set output to output & x & "," & y & "," & ww & "," & hh & "|||"
                end repeat
                return output
            end tell
        """)

        var error: NSDictionary?
        guard let nameResult = nameScript?.executeAndReturnError(&error).stringValue,
              let posResult = posScript?.executeAndReturnError(&error).stringValue else {
            return []
        }

        let names = nameResult.components(separatedBy: "|||").filter { !$0.isEmpty }
        let positions = posResult.components(separatedBy: "|||").filter { !$0.isEmpty }

        guard names.count == positions.count else { return [] }

        let screenHeight = NSScreen.main?.frame.height ?? 900
        var results: [DetectedPokerWindow] = []

        for (index, name) in names.enumerated() {
            // Skip lobby window
            if name.lowercased().contains("lobby") { continue }
            // Only include table windows (contain game type)
            guard name.contains("Hold'em") || name.contains("Omaha") else { continue }

            // Parse position
            let parts = positions[index].components(separatedBy: ",")
            guard parts.count == 4,
                  let x = Double(parts[0].trimmingCharacters(in: CharacterSet.whitespaces)),
                  let y = Double(parts[1].trimmingCharacters(in: CharacterSet.whitespaces)),
                  let w = Double(parts[2].trimmingCharacters(in: CharacterSet.whitespaces)),
                  let h = Double(parts[3].trimmingCharacters(in: CharacterSet.whitespaces)) else { continue }

            // Convert from AppleScript coordinates (top-left origin) to NSScreen (bottom-left origin)
            let flippedY = screenHeight - CGFloat(y) - CGFloat(h)
            let frame = NSRect(x: CGFloat(x), y: flippedY, width: CGFloat(w), height: CGFloat(h))

            // Extract table name from window title (between ] and " -")
            let tableName = extractTableName(from: name)

            results.append(DetectedPokerWindow(
                windowID: CGWindowID(index),
                windowName: name,
                tableName: tableName,
                frame: frame,
                ownerName: "PokerStars"
            ))
        }

        return results
    }

    /// Extract the table name from a PokerStars window title
    /// e.g. "[ID ADM: ...]Chrysothemis V - No Limit Hold'em..." -> "Chrysothemis V"
    private static func extractTableName(from windowTitle: String) -> String {
        var title = windowTitle

        // Remove everything before the last ']'
        if let lastBracket = title.lastIndex(of: "]") {
            title = String(title[title.index(after: lastBracket)...])
        }

        // Take everything before " - "
        if let dashRange = title.range(of: " - ") {
            title = String(title[..<dashRange.lowerBound])
        }

        return title.trimmingCharacters(in: CharacterSet.whitespaces)
    }

    // MARK: - CGWindowList fallback

    private static func getWindowsViaCGWindowList() -> [DetectedPokerWindow] {
        var results: [DetectedPokerWindow] = []

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return results
        }

        let screenHeight = NSScreen.main?.frame.height ?? 900

        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  ownerName.lowercased().contains("pokerstars") else { continue }
            guard !ownerName.contains("PokerHUD") else { continue }

            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat else { continue }

            guard let windowID = window[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard width > 600 && height > 400 else { continue }

            let windowName = window[kCGWindowName as String] as? String ?? ""

            let flippedY = screenHeight - y - height
            let frame = NSRect(x: x, y: flippedY, width: width, height: height)

            results.append(DetectedPokerWindow(
                windowID: windowID,
                windowName: windowName,
                tableName: "",
                frame: frame,
                ownerName: ownerName
            ))
        }

        return results
    }

    // MARK: - Seat Positions

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
        let top = y + h
        let bot = y

        let visualSlots6: [CGPoint] = [
            CGPoint(x: x + w * 0.40, y: bot + h * 0.10),
            CGPoint(x: x + w * 0.02, y: bot + h * 0.35),
            CGPoint(x: x + w * 0.05, y: top - h * 0.35),
            CGPoint(x: x + w * 0.38, y: top - h * 0.18),
            CGPoint(x: x + w * 0.70, y: top - h * 0.35),
            CGPoint(x: x + w * 0.72, y: bot + h * 0.35),
        ]

        let visualSlots9: [CGPoint] = [
            CGPoint(x: x + w * 0.42, y: bot + h * 0.10),
            CGPoint(x: x + w * 0.02, y: bot + h * 0.22),
            CGPoint(x: x + w * 0.02, y: bot + h * 0.42),
            CGPoint(x: x + w * 0.08, y: top - h * 0.30),
            CGPoint(x: x + w * 0.32, y: top - h * 0.18),
            CGPoint(x: x + w * 0.55, y: top - h * 0.18),
            CGPoint(x: x + w * 0.72, y: top - h * 0.30),
            CGPoint(x: x + w * 0.78, y: bot + h * 0.42),
            CGPoint(x: x + w * 0.70, y: bot + h * 0.22),
        ]

        let slots = tableSize <= 6 ? visualSlots6 : visualSlots9
        let maxSeats = tableSize <= 6 ? 6 : 9

        var result: [Int: CGPoint] = [:]
        for seatNumber in occupiedSeats {
            let offset = (seatNumber - heroSeat + maxSeats) % maxSeats
            if offset < slots.count {
                result[seatNumber] = slots[offset]
            }
        }
        return result
    }
}

extension PokerStarsWindowDetector {
    static func hasScreenRecordingPermission() -> Bool {
        !getWindowsViaAppleScript().isEmpty
    }

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
    let tableName: String   // Extracted clean table name (e.g. "Chrysothemis V")
    let frame: NSRect
    let ownerName: String
}
