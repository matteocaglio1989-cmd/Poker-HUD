import Foundation
import Combine
import AppKit

@MainActor
class AppState: ObservableObject {
    // MARK: - Phase 1 State
    @Published var isImporting = false
    @Published var importProgress: Double = 0.0
    @Published var selectedSite: Site?
    @Published var activeTables: [TableInfo] = []
    @Published var currentSession: Session?

    // MARK: - Phase 2 HUD State
    @Published var hudEnabled: Bool = false
    @Published var managedTables: [ActiveTable] = []
    @Published var isFileWatcherActive: Bool = false
    @Published var handHistoryPath: String? = nil
    @Published var hudConfiguration: HUDConfiguration = .standard
    @Published var autoImportLog: [AutoImportEvent] = []
    @Published var lastAutoImportTime: Date? = nil

    // MARK: - Services
    let databaseManager: DatabaseManager
    let importEngine: ImportEngine
    let statsCalculator: StatsCalculator
    // TableManager used only for matching logic, not as source of truth
    var hudManager: HUDManager?
    var fileWatcher: FileWatcher?
    private var fileWatcherCancellable: AnyCancellable?

    init() {
        self.databaseManager = DatabaseManager.shared
        self.statsCalculator = StatsCalculator(databaseManager: databaseManager)
        self.importEngine = ImportEngine(
            databaseManager: databaseManager,
            statsCalculator: statsCalculator
        )
        self.hudManager = HUDManager()

        // Restore saved hand history path and auto-start file watcher
        if let savedPath = UserDefaults.standard.string(forKey: "handHistoryPath") {
            let url = URL(fileURLWithPath: savedPath)
            if FileManager.default.fileExists(atPath: savedPath) {
                startFileWatcher(directory: url)
            } else {
                handHistoryPath = savedPath
            }
        }
    }

    // MARK: - Phase 1 Import

    @discardableResult
    func importHandHistoryFiles(_ urls: [URL]) async throws -> ImportResult {
        await MainActor.run {
            isImporting = true
            importProgress = 0.0
        }

        defer {
            Task { @MainActor in
                isImporting = false
                importProgress = 0.0
            }
        }

        return try await importEngine.importFiles(urls) { progress in
            Task { @MainActor in
                self.importProgress = progress
            }
        }
    }

    // MARK: - Phase 2 HUD Management

    /// Add a new table for HUD tracking
    func addTable(name: String, tableSize: Int = 6, stakes: String = "0.5/1.0") {
        let table = ActiveTable(tableName: name, stakes: stakes, tableSize: tableSize)
        managedTables.append(table)
    }

    /// Remove a table
    func removeTable(id: UUID) {
        if let table = managedTables.first(where: { $0.id == id }) {
            hudManager?.hideHUD(for: table)
        }
        managedTables.removeAll { $0.id == id }
    }

    /// Show HUD panels for a table
    func showHUD(for table: ActiveTable) {
        guard hudEnabled else { return }
        hudManager?.refreshAllStats(tables: [table])
        hudManager?.showHUD(for: table)
    }

    /// Hide HUD panels for a table
    func hideHUD(for table: ActiveTable) {
        hudManager?.hideHUD(for: table)
    }

    /// Hide all HUD panels
    func hideAllHUDs() {
        hudManager?.hideAll()
        for i in managedTables.indices {
            managedTables[i].isHUDVisible = false
        }
    }

    // MARK: - File Watcher

    /// Start watching a directory for new hand history files
    func startFileWatcher(directory: URL) {
        fileWatcher = FileWatcher()

        fileWatcherCancellable = fileWatcher?.fileChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                Task { @MainActor [weak self] in
                    await self?.handleFileWatcherEvent(url: url)
                }
            }

        fileWatcher?.startWatching(directory: directory)
        isFileWatcherActive = true
        handHistoryPath = directory.path
        UserDefaults.standard.set(directory.path, forKey: "handHistoryPath")
    }

    /// Stop the file watcher
    func stopFileWatcher() {
        fileWatcherCancellable?.cancel()
        fileWatcher?.stopWatching()
        fileWatcher = nil
        isFileWatcherActive = false
    }

    /// Pick a hand history directory via open panel
    func pickHandHistoryDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your PokerStars hand history folder"

        if panel.runModal() == .OK, let url = panel.url {
            startFileWatcher(directory: url)
        }
    }

    /// Handle a file change event from the watcher
    private func handleFileWatcherEvent(url: URL) async {
        let filename = url.lastPathComponent
        do {
            let result = try await importEngine.importFileForHUD(url)

            let event = AutoImportEvent(
                timestamp: Date(),
                filename: filename,
                handsImported: result.handsImported,
                handsSkipped: result.handsParsed - result.handsImported,
                playersAffected: result.affectedPlayerNames.count,
                success: true
            )
            autoImportLog.insert(event, at: 0)
            if autoImportLog.count > 50 { autoImportLog.removeLast() }

            if result.handsImported > 0 {
                lastAutoImportTime = Date()
                // Refresh HUD panels for affected players
                let visibleTables = managedTables.filter { $0.isHUDVisible }
                hudManager?.handleNewHands(result: result, tables: visibleTables)
            }
        } catch {
            let event = AutoImportEvent(
                timestamp: Date(),
                filename: filename,
                handsImported: 0,
                handsSkipped: 0,
                playersAffected: 0,
                success: false,
                errorMessage: error.localizedDescription
            )
            autoImportLog.insert(event, at: 0)
            if autoImportLog.count > 50 { autoImportLog.removeLast() }
            print("[AppState] File watcher import error: \(error)")
        }
    }
}

struct TableInfo: Identifiable {
    let id = UUID()
    let tableName: String
    let site: String
    let stakes: String
    let playerCount: Int
}

/// A single auto-import event for the activity log
struct AutoImportEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let filename: String
    let handsImported: Int    // newly imported
    let handsSkipped: Int     // already in DB (duplicates)
    let playersAffected: Int
    let success: Bool
    var errorMessage: String? = nil
}
