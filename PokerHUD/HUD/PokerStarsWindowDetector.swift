import AppKit

/// Detects PokerStars table windows by running osascript to read window titles and positions.
/// Results are cached and refreshed on a background thread every 2 seconds.
class PokerStarsWindowDetector {

    /// Shared instance manages the background refresh
    static let shared = PokerStarsWindowDetector()

    private var cache: [DetectedPokerWindow] = []
    private let lock = NSLock()
    private var refreshTimer: Timer?

    private init() {}

    /// Start periodic background refresh
    func startRefreshing() {
        guard refreshTimer == nil else { return }
        // Initial fetch
        refresh()
        // Refresh every 2 seconds on the main run loop (timer fires on main, work dispatched to background)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Get cached table windows (fast, no blocking)
    var tableWindows: [DetectedPokerWindow] {
        lock.lock()
        defer { lock.unlock() }
        return cache
    }

    /// Find window for a specific table name
    func window(forTable tableName: String) -> DetectedPokerWindow? {
        tableWindows.first { $0.tableName == tableName }
    }

    /// Trigger a refresh (runs osascript on background thread)
    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let windows = Self.runOsascript()
            self?.lock.lock()
            self?.cache = windows
            self?.lock.unlock()
        }
    }

    // MARK: - osascript execution

    private static func runOsascript() -> [DetectedPokerWindow] {
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
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
              !output.isEmpty else {
            return []
        }

        return parseOutput(output)
    }

    private static func parseOutput(_ output: String) -> [DetectedPokerWindow] {
        let screenHeight = NSScreen.main?.frame.height ?? 2160
        var results: [DetectedPokerWindow] = []

        let entries = output.components(separatedBy: "|||")
        for entry in entries {
            let trimmed = entry.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Split "WINDOWTITLE:::x,y,w,h"
            guard let separatorRange = trimmed.range(of: ":::") else { continue }
            let name = String(trimmed[..<separatorRange.lowerBound])
            let coordString = String(trimmed[separatorRange.upperBound...])

            // Only include poker table windows
            guard name.contains("Hold'em") || name.contains("Omaha") else { continue }
            if name.lowercased().contains("lobby") { continue }

            // Parse coordinates
            let coords = coordString.components(separatedBy: ",")
            guard coords.count == 4,
                  let x = Double(coords[0]),
                  let y = Double(coords[1]),
                  let w = Double(coords[2]),
                  let h = Double(coords[3]) else { continue }

            // Convert AppleScript coords (top-left origin) to NSScreen (bottom-left origin)
            let flippedY = screenHeight - CGFloat(y) - CGFloat(h)
            let frame = NSRect(x: CGFloat(x), y: flippedY, width: CGFloat(w), height: CGFloat(h))

            // Extract table name: everything after last ']' and before ' - '
            let tableName = extractTableName(from: name)

            results.append(DetectedPokerWindow(
                tableName: tableName,
                frame: frame,
                fullTitle: name
            ))
        }

        return results
    }

    private static func extractTableName(from windowTitle: String) -> String {
        var title = windowTitle
        if let lastBracket = title.lastIndex(of: "]") {
            title = String(title[title.index(after: lastBracket)...])
        }
        if let dashRange = title.range(of: " - ") {
            title = String(title[..<dashRange.lowerBound])
        }
        return title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}

/// A detected PokerStars table window
struct DetectedPokerWindow {
    let tableName: String   // e.g. "Piazzia V"
    let frame: NSRect       // in NSScreen coordinates (bottom-left origin)
    let fullTitle: String   // full window title
}
