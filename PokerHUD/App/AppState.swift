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
    @Published var hudEnabled: Bool = true
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
    let authService: AuthService
    let subscriptionManager: SubscriptionManager
    let usageTracker: UsageTracker
    /// Single shared Combine bus from `ImportEngine` to `HUDManager`.
    /// Constructed here and injected into both so neither has to know
    /// about the other. Do not construct a second instance.
    let handImportPublisher: HandImportPublisher
    // TableManager used only for matching logic, not as source of truth
    var hudManager: HUDManager?
    var menuBarController: MenuBarController?
    var fileWatcher: FileWatcher?
    private var fileWatcherCancellable: AnyCancellable?
    private var authCancellable: AnyCancellable?
    private var subscriptionCancellable: AnyCancellable?
    private var didRunPostAuthSetup: Bool = false

    init() {
        self.databaseManager = DatabaseManager.shared
        self.statsCalculator = StatsCalculator(databaseManager: databaseManager)
        self.handImportPublisher = HandImportPublisher()
        self.importEngine = ImportEngine(
            databaseManager: databaseManager,
            statsCalculator: statsCalculator,
            importPublisher: handImportPublisher
        )
        let hud = HUDManager()
        hud.subscribeToHandImports(handImportPublisher)
        self.hudManager = hud
        self.authService = AuthService()
        self.subscriptionManager = SubscriptionManager()
        self.usageTracker = UsageTracker(subscriptionManager: self.subscriptionManager)
        self.menuBarController = nil // Set after init since it needs self

        // Request Accessibility permission (preferred path — lets AX read
        // PokerStars window titles regardless of Screen Recording status).
        // `ensureGranted(prompt: true)` shows the standard macOS dialog at
        // most once per process lifetime. The user has to act in System
        // Settings, so this typically returns false on first launch; the
        // permission flips to granted on the next relaunch.
        AccessibilityPermission.ensureGranted(prompt: true)

        // Request Screen Recording as a fallback path for window titles.
        // When Accessibility is granted this is optional, but we still
        // prompt because some users already have it on and removing the
        // prompt would silently regress their binding path.
        if !PokerStarsWindowDetector.hasScreenRecordingPermission() {
            PokerStarsWindowDetector.requestScreenRecordingPermission()
        }

        // Republish auth changes through AppState so SwiftUI views observing
        // AppState re-render when the user signs in/out.
        authCancellable = authService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                Task { @MainActor [weak self] in
                    self?.handleAuthChange()
                }
            }

        // Republish subscription changes so the root router re-renders when
        // the entitlement flips (trial countdown, purchase, expiry).
        subscriptionCancellable = subscriptionManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

        // Try to restore a persisted session from the Keychain.
        Task { @MainActor in
            await authService.restoreSession()
        }
    }

    /// Called whenever the auth state may have changed. Runs post-login
    /// setup exactly once per signed-in session, and tears down on sign-out.
    private func handleAuthChange() {
        if authService.isAuthenticated {
            if !didRunPostAuthSetup {
                didRunPostAuthSetup = true
                onAuthenticated()
            }
        } else {
            if didRunPostAuthSetup {
                didRunPostAuthSetup = false
                onSignedOut()
            }
        }
    }

    /// Setup that should only happen after the user is signed in: load the
    /// subscription entitlement, start the trial usage tracker, and — only
    /// when the entitlement grants access — restore the saved hand history
    /// path and start watching it.
    private func onAuthenticated() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.subscriptionManager.loadProducts()
            await self.subscriptionManager.refreshEntitlement()
            self.usageTracker.start()

            // Only auto-start the file watcher if the user actually has
            // access (trial with time remaining or active subscription).
            // Unsubscribed users will hit the paywall instead, and we don't
            // want background imports happening behind it.
            if self.subscriptionManager.entitlement.grantsAccess,
               let savedPath = UserDefaults.standard.string(forKey: "handHistoryPath") {
                let url = URL(fileURLWithPath: savedPath)
                if FileManager.default.fileExists(atPath: savedPath) {
                    self.startFileWatcher(directory: url)
                } else {
                    self.handHistoryPath = savedPath
                }
            }
        }
    }

    /// Tear down user-scoped state when the user signs out.
    private func onSignedOut() {
        stopFileWatcher()
        hideAllHUDs()
        managedTables.removeAll()
        autoImportLog.removeAll()
        handHistoryPath = nil
        usageTracker.stop()
        subscriptionManager.reset()
    }

    /// Initialize the menu bar icon (must be called after init since it needs `self`)
    func setupMenuBar() {
        if menuBarController == nil {
            menuBarController = MenuBarController(appState: self)
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

                // Auto-create/update tables and show HUD. Stats for newly
                // created panels are pre-fetched inside `HUDManager.showHUD`,
                // and stats for panels on already-tracked tables are
                // refreshed via the `HandImportPublisher` subscription that
                // `HUDManager` installed in its init — no direct
                // `handleNewHands` call is needed here.
                autoManageTables(from: result)
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

    // MARK: - Auto Table Management

    /// Automatically create/update tables from imported hand data and show HUD
    private func autoManageTables(from result: HUDImportResult) {
        guard hudEnabled else { return }

        for (tableName, seats) in result.tableSeats {
            // Check if we already have this table
            if let existingIndex = managedTables.firstIndex(where: { $0.tableName == tableName }) {
                // Update seat assignments with latest player positions
                updateTableSeats(at: existingIndex, with: seats)

                // Auto-show HUD if not already visible
                if !managedTables[existingIndex].isHUDVisible {
                    managedTables[existingIndex].isHUDVisible = true
                    hudManager?.showHUD(for: managedTables[existingIndex])
                }
            } else {
                // Create new table automatically
                let tableSize = seats.first?.tableSize ?? 6
                let stakes = seats.first?.stakes ?? "?"

                var seatAssignments = SeatAssignment.defaultLayout(for: tableSize)
                for seatInfo in seats {
                    if let idx = seatAssignments.firstIndex(where: { $0.seatNumber == seatInfo.seatNumber }) {
                        seatAssignments[idx].playerName = seatInfo.playerName
                    }
                }

                var table = ActiveTable(
                    tableName: tableName,
                    site: "PokerStars",
                    stakes: stakes,
                    tableSize: tableSize,
                    seatAssignments: seatAssignments,
                    isHUDVisible: true
                )
                // Override with populated seats
                table.seatAssignments = seatAssignments

                managedTables.append(table)

                // Try to bind this new table to the correct PokerStars window
                // CGWindowList returns windows front-to-back, so the first unbound
                // window is most likely the one that just generated this hand
                let windows = PokerStarsWindowDetector.findTableWindows()
                let boundIDs = Set(hudManager?.getAllBoundWindowIDs() ?? [])
                // Try name match first (if Screen Recording permission granted)
                if let named = windows.first(where: { !$0.windowName.isEmpty && $0.windowName.contains(tableName) }) {
                    hudManager?.bindTable(table.id, toWindow: named.windowID)
                    print("[AppState] Bound new table '\(tableName)' to window \(named.windowID) by name")
                } else if let unbound = windows.first(where: { !boundIDs.contains($0.windowID) }) {
                    hudManager?.bindTable(table.id, toWindow: unbound.windowID)
                    print("[AppState] Bound new table '\(tableName)' to window \(unbound.windowID) (frontmost unbound)")
                }

                hudManager?.showHUD(for: table)
                print("[AppState] Auto-created table: \(tableName) with \(seats.count) players")
            }
        }
    }

    /// Update seat assignments for an existing table and handle player changes.
    /// Adds new players, updates changed seats, and removes players who left.
    private func updateTableSeats(at index: Int, with seats: [TableSeatInfo]) {
        var changed = false
        let newPlayerNames = Set(seats.map { $0.playerName })

        // 1. Remove panels for players who are no longer at the table
        for seatIdx in managedTables[index].seatAssignments.indices {
            let seat = managedTables[index].seatAssignments[seatIdx]
            guard let oldPlayer = seat.playerName, !oldPlayer.isEmpty else { continue }

            if !newPlayerNames.contains(oldPlayer) {
                // This player left the table
                let key = PanelKey(tableId: managedTables[index].id, seatNumber: seat.seatNumber)
                hudManager?.removeSinglePanel(key: key)
                managedTables[index].seatAssignments[seatIdx].playerName = nil
                print("[AppState] Player left: \(oldPlayer) from seat \(seat.seatNumber)")
                changed = true
            }
        }

        // 2. Update/add players at their current seats
        for seatInfo in seats {
            if let seatIdx = managedTables[index].seatAssignments.firstIndex(where: { $0.seatNumber == seatInfo.seatNumber }) {
                let oldPlayer = managedTables[index].seatAssignments[seatIdx].playerName

                if oldPlayer != seatInfo.playerName {
                    // Player changed at this seat — remove old panel
                    if oldPlayer != nil {
                        let key = PanelKey(tableId: managedTables[index].id, seatNumber: seatInfo.seatNumber)
                        hudManager?.removeSinglePanel(key: key)
                    }
                    managedTables[index].seatAssignments[seatIdx].playerName = seatInfo.playerName
                    print("[AppState] Seat \(seatInfo.seatNumber): \(oldPlayer ?? "empty") -> \(seatInfo.playerName)")
                    changed = true
                }
            }
        }

        // 3. Show new/updated panels
        if changed && managedTables[index].isHUDVisible {
            hudManager?.showHUD(for: managedTables[index])
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
