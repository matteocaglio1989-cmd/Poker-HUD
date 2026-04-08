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

    /// IDs of tables added by `autoManageTables` (i.e. derived from imported
    /// hand histories). These are eligible for automatic pruning when their
    /// PokerStars window closes. Tables added manually via TableSetupView's
    /// "Add Table" button are **not** in this set and are never auto-pruned.
    private var autoCreatedTableIDs: Set<UUID> = []

    /// URL of the hand-history directory currently being accessed via a
    /// security-scoped bookmark, or `nil` if the file watcher isn't
    /// running. Retained so `stopFileWatcher()` can call
    /// `stopAccessingSecurityScopedResource()` on the same URL that
    /// `startAccessingSecurityScopedResource()` was called on — calling
    /// stop on a different URL is a no-op.
    private var activeScopedHandHistoryURL: URL?

    /// UserDefaults key holding the security-scoped bookmark `Data` for
    /// the hand-history directory. Under App Sandbox the raw path stored
    /// in `handHistoryPath` is not re-openable across launches; the
    /// bookmark is the only way to restore access.
    private static let handHistoryBookmarkKey = "handHistoryBookmark"

    /// Legacy key that used to hold a plain path string. Still written
    /// for display purposes (the Dashboard's auto-import strip shows the
    /// folder path), and consumed as a fallback on first launch after
    /// the App Sandbox migration so users with a pre-sandbox install
    /// get a single "please re-pick your folder" prompt instead of a
    /// silent permission denial.
    private static let handHistoryPathKey = "handHistoryPath"

    /// Set to `true` after `onAuthenticated` detects a legacy
    /// `handHistoryPath` without a matching bookmark. Consumed by
    /// `SettingsView` / `TableSetupView` to show a "please re-pick
    /// your folder" banner. Resets to `false` once the user completes
    /// a fresh `pickHandHistoryDirectory()`.
    @Published var needsHandHistoryDirectoryReselection: Bool = false

    /// Periodic sweep that calls `pruneClosedTables()` every 30s. Covers the
    /// case where the user closes all tables and stops playing so no more
    /// file-watcher events fire to piggyback on. Started in `onAuthenticated`
    /// and stopped in `onSignedOut`.
    private var pruneTimer: Timer?

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
            self.startPruneTimer()

            // Only auto-start the file watcher if the user actually has
            // access (trial with time remaining or active subscription).
            // Unsubscribed users will hit the paywall instead, and we
            // don't want background imports happening behind it.
            guard self.subscriptionManager.entitlement.grantsAccess else { return }
            self.restoreHandHistoryDirectoryFromBookmark()
        }
    }

    /// Try to resolve the saved security-scoped bookmark and restart the
    /// file watcher against it. Called from `onAuthenticated` on every
    /// launch. If the bookmark is missing or stale, falls back to either
    /// the legacy raw-path UserDefaults key (sets
    /// `needsHandHistoryDirectoryReselection` so the UI can prompt) or a
    /// clean "no folder picked yet" state.
    private func restoreHandHistoryDirectoryFromBookmark() {
        let defaults = UserDefaults.standard

        if let bookmark = defaults.data(forKey: Self.handHistoryBookmarkKey) {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmark,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    // macOS asks us to refresh the bookmark — easiest
                    // path is to re-pick. Flag the UI and bail out.
                    Log.app.warning("Hand-history bookmark is stale; prompting for re-pick")
                    defaults.removeObject(forKey: Self.handHistoryBookmarkKey)
                    needsHandHistoryDirectoryReselection = true
                    return
                }
                guard url.startAccessingSecurityScopedResource() else {
                    Log.app.error("startAccessingSecurityScopedResource() returned false for saved bookmark")
                    needsHandHistoryDirectoryReselection = true
                    return
                }
                // Hold the access open for the lifetime of the watcher;
                // `stopFileWatcher` calls stopAccessing on this URL.
                activeScopedHandHistoryURL = url
                handHistoryPath = url.path
                startFileWatcherInternal(directory: url)
                return
            } catch {
                Log.app.error("Failed to resolve hand-history bookmark: \(error.localizedDescription, privacy: .public)")
                defaults.removeObject(forKey: Self.handHistoryBookmarkKey)
                needsHandHistoryDirectoryReselection = true
                return
            }
        }

        // No bookmark — check for the legacy raw-path key and prompt
        // the user to re-pick if it exists. Under App Sandbox the raw
        // path is non-accessible without a fresh NSOpenPanel grant.
        if let legacyPath = defaults.string(forKey: Self.handHistoryPathKey), !legacyPath.isEmpty {
            handHistoryPath = legacyPath
            needsHandHistoryDirectoryReselection = true
            Log.app.debug("Legacy handHistoryPath present but no bookmark — asking user to re-pick")
        }
    }

    /// Tear down user-scoped state when the user signs out.
    private func onSignedOut() {
        stopFileWatcher()
        stopPruneTimer()
        hideAllHUDs()
        managedTables.removeAll()
        autoCreatedTableIDs.removeAll()
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

        let result = try await importEngine.importFiles(urls) { progress in
            Task { @MainActor in
                self.importProgress = progress
            }
        }
        // Tick down the 100-hand free trial (no-op if already subscribed).
        usageTracker.recordHandsImported(result.handsImported)
        return result
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
        // Drop the auto-created marker too so a manual deletion doesn't
        // leak into the prune set (and so re-adding a table with the same
        // id after a manual delete starts fresh).
        autoCreatedTableIDs.remove(id)
    }

    // MARK: - Auto-prune closed tables

    /// Remove auto-created tables whose PokerStars window is no longer
    /// open. The user doesn't want stale rows lingering in HUD Setup after
    /// they close a table — this runs on every file-watcher event and on
    /// a 30s periodic timer.
    ///
    /// "Closed" means neither of these signals fires for the table:
    ///
    ///   1. A current PokerStars window's title contains the table name
    ///      (strong signal, requires Screen Recording or Accessibility)
    ///   2. The cached binding's windowID is still in the live window list
    ///      (title-less fallback; if no binding exists yet the table is
    ///      treated as newborn-alive to avoid pruning before its first
    ///      reposition tick)
    ///
    /// Manually-added tables (not in `autoCreatedTableIDs`) are skipped —
    /// users expect those to persist until they explicitly delete them.
    private func pruneClosedTables() {
        guard hudEnabled else { return }
        let windows = PokerStarsWindowDetector.findTableWindows()
        let liveWindowIDs = Set(windows.map { $0.windowID })
        // When there's no PokerStars running at all, every auto-created
        // table is stale (possibly imported from a leftover hand history
        // file with no live table) and should be pruned regardless of
        // the binding cache state. The "no binding → newborn, don't
        // prune" escape below is only sensible when SOME PokerStars
        // windows exist — otherwise there's nothing to be newborn
        // against.
        let noWindowsAtAll = windows.isEmpty

        let toRemove: [UUID] = managedTables.compactMap { table in
            guard autoCreatedTableIDs.contains(table.id) else { return nil }

            // Signal 1: a live window's title still matches this table.
            if windows.contains(where: { !$0.windowName.isEmpty && $0.windowName.contains(table.tableName) }) {
                return nil
            }

            // Signal 2: cached binding points at a live windowID.
            if let boundID = hudManager?.boundWindowID(for: table.id) {
                if liveWindowIDs.contains(boundID) {
                    return nil
                }
            } else if !noWindowsAtAll {
                // Some PokerStars windows exist but this table hasn't
                // been bound yet — newborn, give it a chance.
                return nil
            }

            // Neither signal fired (or there's nothing running at all) —
            // table is closed.
            return table.id
        }

        for id in toRemove {
            let name = managedTables.first(where: { $0.id == id })?.tableName ?? "?"
            Log.app.debug("Auto-pruning closed table '\(name, privacy: .public)' (id=\(id, privacy: .public))")
            removeTable(id: id)
        }
    }

    private func startPruneTimer() {
        pruneTimer?.invalidate()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pruneClosedTables()
            }
        }
    }

    private func stopPruneTimer() {
        pruneTimer?.invalidate()
        pruneTimer = nil
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

    /// Public entry point for starting the file watcher on a freshly-
    /// picked URL (typically from `NSOpenPanel`). Captures a security-
    /// scoped bookmark and persists it to UserDefaults so the directory
    /// survives across app relaunches under App Sandbox.
    ///
    /// Under sandbox, the URL returned by NSOpenPanel already has
    /// security scope active for the current session, so we do NOT
    /// call `startAccessingSecurityScopedResource()` here — we just
    /// capture the bookmark and hand off to the internal starter. On
    /// subsequent launches, `restoreHandHistoryDirectoryFromBookmark`
    /// calls `startAccessingSecurityScopedResource()` before restarting
    /// the watcher.
    func startFileWatcher(directory: URL) {
        // Capture the security-scoped bookmark for future launches.
        // `.withSecurityScope` makes the bookmark usable across app
        // restarts under App Sandbox.
        do {
            let bookmark = try directory.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.handHistoryBookmarkKey)
            activeScopedHandHistoryURL = directory
        } catch {
            // If bookmark capture fails (e.g. outside sandbox, or some
            // filesystem oddity), continue without it — the watcher
            // still works for the current session, it just won't
            // survive a relaunch. Log loudly so we can diagnose.
            Log.app.error("Failed to capture security-scoped bookmark for hand history dir: \(error.localizedDescription, privacy: .public)")
        }

        needsHandHistoryDirectoryReselection = false
        startFileWatcherInternal(directory: directory)
    }

    /// Internal watcher starter, shared between the fresh-pick path
    /// (`startFileWatcher(directory:)`) and the cold-launch restore
    /// path (`restoreHandHistoryDirectoryFromBookmark`). Does not
    /// touch the security scope — callers are responsible for that.
    private func startFileWatcherInternal(directory: URL) {
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
        // Keep the legacy raw-path key in sync for display purposes
        // (the Dashboard's auto-import strip reads it). Bookmarks are
        // the source of truth for sandbox access; the raw path is
        // cosmetic.
        UserDefaults.standard.set(directory.path, forKey: Self.handHistoryPathKey)
    }

    /// Stop the file watcher and release the security-scoped access.
    func stopFileWatcher() {
        fileWatcherCancellable?.cancel()
        fileWatcher?.stopWatching()
        fileWatcher = nil
        isFileWatcherActive = false

        // Release the security-scoped access so the sandbox doesn't
        // leak an open file handle. Safe to call on a URL that never
        // had startAccessing called — it's a no-op in that case.
        if let url = activeScopedHandHistoryURL {
            url.stopAccessingSecurityScopedResource()
            activeScopedHandHistoryURL = nil
        }
    }

    /// Pick a hand history directory via open panel
    func pickHandHistoryDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your PokerStars hand history folder"

        if panel.runModal() == .OK, let url = panel.url {
            // Release any previous scope before replacing with the new
            // one — prevents a double-scoped-access leak if the user
            // re-picks mid-session.
            stopFileWatcher()
            startFileWatcher(directory: url)
        }
    }

    /// Handle a file change event from the watcher
    private func handleFileWatcherEvent(url: URL) async {
        let filename = url.lastPathComponent
        // Piggyback on every import to prune any auto-created tables whose
        // PokerStars window has been closed. This keeps the HUD Setup UI
        // clean during active play without waiting for the 30s timer.
        pruneClosedTables()
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

                // Tick down the 100-hand free trial (no-op if already
                // subscribed). Has to happen on the file-watcher path too,
                // otherwise auto-imported hands wouldn't count.
                usageTracker.recordHandsImported(result.handsImported)

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
            Log.app.error("File watcher import error: \(error.localizedDescription, privacy: .public)")
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
                // Mark this table as auto-created so pruneClosedTables() is
                // allowed to remove it when its PokerStars window closes.
                // Manually-added tables (via TableSetupView "Add Table") are
                // never in this set and are never auto-pruned.
                autoCreatedTableIDs.insert(table.id)

                // Try to bind this new table to the correct PokerStars window.
                //
                // Order of preference:
                //   a) Name match — works whenever Screen Recording OR
                //      Accessibility permission is granted (the AX path
                //      enriches CGWindowList titles when SR is denied).
                //   b) First unbound — CGWindowList returns front-to-back,
                //      so the frontmost unbound window is usually right
                //      for a single-table session. With multiple unbound
                //      windows this is inherently ambiguous (the multi-
                //      table launch bug) but it's better to bind something
                //      than to leave the HUD invisible. HUDManager.findWindowFrame's
                //      cache validation auto-corrects any wrong initial
                //      binding on the next reposition tick (every 500 ms)
                //      once titles become readable.
                let windows = PokerStarsWindowDetector.findTableWindows()
                let boundIDs = Set(hudManager?.getAllBoundWindowIDs() ?? [])
                let unboundWindows = windows.filter { !boundIDs.contains($0.windowID) }

                if let named = windows.first(where: { !$0.windowName.isEmpty && $0.windowName.contains(tableName) }) {
                    hudManager?.bindTable(table.id, toWindow: named.windowID)
                    Log.app.debug("Bound new table '\(tableName, privacy: .public)' to window \(named.windowID) by name")
                } else if let unbound = unboundWindows.first {
                    hudManager?.bindTable(table.id, toWindow: unbound.windowID)
                    if unboundWindows.count > 1 {
                        Log.app.warning("Bound '\(tableName, privacy: .public)' to window \(unbound.windowID) but \(unboundWindows.count) windows are unbound and titles are unreadable. Grant Accessibility permission in System Settings → Privacy & Security for reliable multi-table binding.")
                    } else {
                        Log.app.debug("Bound new table '\(tableName, privacy: .public)' to only unbound window \(unbound.windowID)")
                    }
                }

                hudManager?.showHUD(for: table)
                Log.app.debug("Auto-created table: \(tableName, privacy: .public) with \(seats.count) players")
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
                Log.app.debug("Player left: \(oldPlayer, privacy: .public) from seat \(seat.seatNumber)")
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
                    Log.app.debug("Seat \(seatInfo.seatNumber): \(oldPlayer ?? "empty", privacy: .public) -> \(seatInfo.playerName, privacy: .public)")
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
