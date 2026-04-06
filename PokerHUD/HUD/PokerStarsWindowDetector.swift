import AppKit

/// Detects PokerStars table windows using osascript for reliable window titles
struct PokerStarsWindowDetector {

    /// Cached results
    private static var cachedWindows: [DetectedPokerWindow] = []
    private static var lastDetectionTime: Date = .distantPast
    private static let cacheInterval: TimeInterval = 2.0
    private static var isRunning = false

    /// Find all PokerStars table windows
    static func findTableWindows() -> [DetectedPokerWindow] {
        if Date().timeIntervalSince(lastDetectionTime) < cacheInterval && !cachedWindows.isEmpty {
            return cachedWindows
        }

        // Don't run osascript concurrently
        guard !isRunning else { return cachedWindows }
        isRunning = true
        defer { isRunning = false }

        let windows = runOsascriptDetection()
        if !windows.isEmpty {
            cachedWindows = windows
            lastDetectionTime = Date()
        }
        return cachedWindows
    }

    /// Trigger an async refresh of the window cache (call from background)
    static func refreshCache() {
        DispatchQueue.global(qos: .userInitiated).async {
            let windows = runOsascriptDetection()
            if !windows.isEmpty {
                cachedWindows = windows
                lastDetectionTime = Date()
            }
        }
    }

    // MARK: - osascript detection

    private static func runOsascriptDetection() -> [DetectedPokerWindow] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", """
            tell application "System Events"
                if not (exists process "PokerStars") then return ""
                tell process "PokerStars"
                    set output to ""
                    repeat with w in every window
                        set wName to name of w
                        set {x, y} to position of w
                        set {ww, hh} to size of w
                        set output to output & wName & ":::" & x & "," & y & "," & ww & "," & hh & "|||"
                    end repeat
                    return output
                end tell
            end tell
        """]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            print("[WindowDetector] osascript failed: \(error)")
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
              !output.isEmpty else {
            return []
        }

        return parseOsascriptOutput(output)
    }

    private static func parseOsascriptOutput(_ output: String) -> [DetectedPokerWindow] {
        let entries = output.components(separatedBy: "|||").filter { !$0.isEmpty }
        let screenHeight = NSScreen.main?.frame.height ?? 900
        var results: [DetectedPokerWindow] = []

        for entry in entries {
            let parts = entry.components(separatedBy: ":::")
            guard parts.count == 2 else { continue }

            let name = parts[0].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let coords = parts[1].components(separatedBy: ",")
            guard coords.count == 4,
                  let x = Double(coords[0].trimmingCharacters(in: CharacterSet.whitespaces)),
                  let y = Double(coords[1].trimmingCharacters(in: CharacterSet.whitespaces)),
                  let w = Double(coords[2].trimmingCharacters(in: CharacterSet.whitespaces)),
                  let h = Double(coords[3].trimmingCharacters(in: CharacterSet.whitespaces)) else { continue }

            // Skip lobby and non-table windows
            if name.lowercased().contains("lobby") { continue }
            guard name.contains("Hold'em") || name.contains("Omaha") else { continue }

            let flippedY = screenHeight - CGFloat(y) - CGFloat(h)
            let frame = NSRect(x: CGFloat(x), y: flippedY, width: CGFloat(w), height: CGFloat(h))
            let tableName = extractTableName(from: name)

            // Use a hash of the table name as stable window ID
            let stableID = CGWindowID(abs(tableName.hashValue) % 100000)

            results.append(DetectedPokerWindow(
                windowID: stableID,
                windowName: name,
                tableName: tableName,
                frame: frame,
                ownerName: "PokerStars"
            ))
        }

        return results
    }

    /// Extract table name from window title
    /// "[ID ADM: ...]Chrysothemis V - No Limit Hold'em..." -> "Chrysothemis V"
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

        return title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
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

    // MARK: - Permission check

    static func hasScreenRecordingPermission() -> Bool {
        // osascript-based detection always works, so this is about CGWindowList names
        return false // Always show the hint to grant permission
    }
}

struct DetectedPokerWindow {
    let windowID: CGWindowID
    let windowName: String
    let tableName: String
    let frame: NSRect
    let ownerName: String
}
