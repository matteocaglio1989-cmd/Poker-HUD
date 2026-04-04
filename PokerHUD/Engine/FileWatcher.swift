import Foundation
import Combine

/// Monitors a directory for new or modified hand history files using GCD DispatchSource
class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.pokerhud.filewatcher", qos: .utility)
    private var directoryURL: URL?
    private var fileDescriptor: Int32 = -1
    private var knownFiles: [String: Date] = [:]
    private var debounceWorkItem: DispatchWorkItem?

    /// Publishes URLs of new or modified hand history files
    let fileChanged = PassthroughSubject<URL, Never>()

    /// Whether the watcher is currently active
    private(set) var isWatching = false

    /// Start watching a directory for changes
    func startWatching(directory: URL) {
        stopWatching()

        directoryURL = directory

        // Snapshot existing files so we only emit new ones
        snapshotDirectory(directory)

        fileDescriptor = open(directory.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("[FileWatcher] Failed to open directory: \(directory.path)")
            return
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: queue
        )

        source?.setEventHandler { [weak self] in
            self?.handleDirectoryChange()
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        source?.resume()
        isWatching = true
        print("[FileWatcher] Watching: \(directory.path)")
    }

    /// Stop watching
    func stopWatching() {
        debounceWorkItem?.cancel()
        source?.cancel()
        source = nil
        isWatching = false
        directoryURL = nil
    }

    deinit {
        stopWatching()
    }

    // MARK: - Private

    private func snapshotDirectory(_ directory: URL) {
        knownFiles.removeAll()
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }

        for case let fileURL as URL in enumerator {
            if isHandHistoryFile(fileURL),
               let modDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                knownFiles[fileURL.lastPathComponent] = modDate
            }
        }
    }

    private func handleDirectoryChange() {
        // Debounce: wait 500ms for writes to settle
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.scanForChanges()
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func scanForChanges() {
        guard let directory = directoryURL else { return }

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }

        for case let fileURL as URL in enumerator {
            guard isHandHistoryFile(fileURL) else { continue }

            let filename = fileURL.lastPathComponent
            let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

            if let knownDate = knownFiles[filename] {
                // File was modified
                if modDate > knownDate {
                    knownFiles[filename] = modDate
                    fileChanged.send(fileURL)
                }
            } else {
                // New file
                knownFiles[filename] = modDate
                fileChanged.send(fileURL)
            }
        }
    }

    private func isHandHistoryFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "txt" || ext == "log"
    }
}
