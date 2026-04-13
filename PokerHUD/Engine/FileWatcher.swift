import Foundation
import Combine

/// Monitors a directory tree for new or modified hand history files using periodic polling.
/// DispatchSource only watches a single directory descriptor and misses changes in subdirectories,
/// so we use a timer-based approach that recursively scans the entire directory tree.
class FileWatcher {
    private let queue = DispatchQueue(label: "com.pokerhud.filewatcher", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var directoryURL: URL?
    private var knownFiles: [String: Date] = [:]  // relative path -> modification date
    private let pollInterval: TimeInterval

    /// Publishes URLs of new or modified hand history files
    let fileChanged = PassthroughSubject<URL, Never>()

    /// Whether the watcher is currently active
    private(set) var isWatching = false

    init(pollInterval: TimeInterval = 2.0) {
        self.pollInterval = pollInterval
    }

    /// Start watching a directory (and all subdirectories) for changes
    /// Set importExisting to true to emit all existing files on first scan
    func startWatching(directory: URL, importExisting: Bool = true) {
        stopWatching()
        directoryURL = directory

        if importExisting {
            // Emit all existing files immediately, then track for changes
            emitExistingFiles(in: directory)
        } else {
            // Snapshot existing files so we only emit new/modified ones
            snapshotDirectory(directory)
        }

        // Start periodic polling timer
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            self?.scanForChanges()
        }
        timer.resume()
        self.timer = timer

        isWatching = true
        print("[FileWatcher] Watching (recursive): \(directory.path) every \(pollInterval)s")
    }

    /// Stop watching
    func stopWatching() {
        timer?.cancel()
        timer = nil
        isWatching = false
        directoryURL = nil
        knownFiles.removeAll()
    }

    deinit {
        stopWatching()
    }

    // MARK: - Private

    /// Emit all existing files as new, then snapshot them for future change detection
    private func emitExistingFiles(in directory: URL) {
        knownFiles.removeAll()
        for (relativePath, modDate, fileURL) in enumerateHandHistoryFiles(in: directory) {
            knownFiles[relativePath] = modDate
            fileChanged.send(fileURL)
        }
        print("[FileWatcher] Emitted \(knownFiles.count) existing files for import")
    }

    /// Build initial snapshot of all hand history files in the directory tree
    private func snapshotDirectory(_ directory: URL) {
        knownFiles.removeAll()
        for (relativePath, modDate, _) in enumerateHandHistoryFiles(in: directory) {
            knownFiles[relativePath] = modDate
        }
        print("[FileWatcher] Snapshot: \(knownFiles.count) existing files")
    }

    /// Scan for new or modified files and emit them
    private func scanForChanges() {
        guard let directory = directoryURL else { return }

        for (relativePath, modDate, fileURL) in enumerateHandHistoryFiles(in: directory) {
            if let knownDate = knownFiles[relativePath] {
                // File was modified since last scan
                if modDate > knownDate {
                    knownFiles[relativePath] = modDate
                    fileChanged.send(fileURL)
                    print("[FileWatcher] Modified: \(relativePath)")
                }
            } else {
                // New file discovered
                knownFiles[relativePath] = modDate
                fileChanged.send(fileURL)
                print("[FileWatcher] New file: \(relativePath)")
            }
        }
    }

    /// Recursively enumerate all hand history files in a directory tree
    /// Returns: [(relativePath, modificationDate, absoluteURL)]
    private func enumerateHandHistoryFiles(in directory: URL) -> [(String, Date, URL)] {
        var results: [(String, Date, URL)] = []

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return results }

        let basePath = directory.path

        for case let fileURL as URL in enumerator {
            // Skip directories
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  resourceValues.isRegularFile == true,
                  let modDate = resourceValues.contentModificationDate else {
                continue
            }

            guard isHandHistoryFile(fileURL) else { continue }

            // Use relative path as unique key (handles subfolders like logitech6942/HH2025...)
            let relativePath = String(fileURL.path.dropFirst(basePath.count + 1))
            results.append((relativePath, modDate, fileURL))
        }

        return results
    }

    /// Check if a file looks like a hand history file
    private func isHandHistoryFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ext == "txt" || ext == "log" else { return false }

        // Extra safety: skip very small files (likely not hand histories)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 50
    }
}
