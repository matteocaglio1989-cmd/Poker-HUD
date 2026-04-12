import AppKit
import SwiftUI
import Combine
import GRDB

/// Manages all HUD overlay panels — creates, positions, refreshes, and destroys them.
/// Panel positions are stored as fractional offsets relative to the poker table window,
/// so they work across any window size and position.
@MainActor
class HUDManager {
    private var panels: [PanelKey: HUDPanel] = [:]
    /// Reactive state per panel. Mutating a state object here causes the
    /// corresponding `HUDContentView` to re-render without us having to
    /// swap out the underlying `NSHostingView`, which is what lets the
    /// flash-border animation in `HUDContentView` actually run to
    /// completion instead of being torn down on every stats refresh.
    private var panelStates: [PanelKey: HUDPanelState] = [:]
    private var playerStats: [String: PlayerStats] = [:]
    private var configuration: HUDConfiguration
    private var positionTimer: Timer?
    private var trackedTables: [ActiveTable] = []
    private var tableWindowBinding: [UUID: CGWindowID] = [:]
    /// Maps PanelKey -> slot index (hero-relative position)
    private var panelSlots: [PanelKey: Int] = [:]
    /// Combine subscription to `HandImportPublisher`. Stored so it lives
    /// for the lifetime of the HUDManager and gets cancelled on deinit.
    private var importSubscription: AnyCancellable?
    /// Workspace observer that hides HUD panels when PokerStars loses
    /// focus and shows them when it regains focus. Without this, the
    /// floating panels would stay on top of every other app's windows.
    private var appActivationObserver: NSObjectProtocol?

    init(configuration: HUDConfiguration = .standard) {
        self.configuration = configuration
        startAppActivationObserver()
    }

    /// Watch for app-activation changes. When PokerStars (or our own
    /// Poker HUD app) is the frontmost app, all panels are shown.
    /// When any other app gains focus, all panels are hidden so they
    /// don't float over unrelated windows.
    private func startAppActivationObserver() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }

                let isPokerStars = app.localizedName?.contains("PokerStars") == true
                let isOurApp = app == NSRunningApplication.current

                if isPokerStars || isOurApp {
                    // Trigger the reposition pass which shows panels
                    // for the frontmost table only.
                    self.repositionAllPanels()
                } else {
                    for panel in self.panels.values {
                        panel.orderOut(nil)
                    }
                }
            }
        }
    }

    /// Subscribe this HUDManager to a `HandImportPublisher`. After this
    /// call, every successful file-watcher import automatically refreshes
    /// stats for affected players on currently-tracked tables — there is
    /// no need for `AppState` to call `handleNewHands(...)` directly.
    ///
    /// Only one subscription is active at a time; calling this method
    /// again replaces the previous one.
    func subscribeToHandImports(_ publisher: HandImportPublisher) {
        importSubscription?.cancel()
        // `handleNewHands` is `@MainActor`-isolated, so the `Task { @MainActor }`
        // is what actually delivers onto the main actor — no additional
        // `.receive(on: DispatchQueue.main)` hop is needed.
        importSubscription = publisher.handsImported
            .sink { result in
                Task { @MainActor [weak self] in
                    self?.handleNewHands(result: result)
                }
            }
    }

    // MARK: - Panel Lifecycle

    func showHUD(for table: ActiveTable) {
        let playerNames = table.seatAssignments.compactMap { $0.playerName }.filter { !$0.isEmpty }
        guard !playerNames.isEmpty else { return }

        let statsRepo = StatsRepository()
        let playerRepo = PlayerRepository()

        for playerName in playerNames {
            do {
                if let player = try playerRepo.fetchByUsername(playerName, siteId: nil),
                   let playerId = player.id,
                   let stats = try statsRepo.fetchPlayerStats(playerId: playerId) {
                    playerStats[playerName] = stats
                }
            } catch {
                Log.hud.error("Error loading \(playerName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        createPanels(for: table)

        if !trackedTables.contains(where: { $0.id == table.id }) {
            trackedTables.append(table)
        }
        startPositionTracking()
    }

    private func createPanels(for table: ActiveTable) {
        // If there's no PokerStars window to overlay, don't create panels
        // at all. The old behaviour fell back to stacking panels at the
        // screen center — which produced a useless row of floating labels
        // whenever the file watcher imported hands from a leftover file
        // with no PokerStars running. The table is still added to
        // `trackedTables` by the caller (`showHUD`) and
        // `repositionAllPanels` will create panels on the next tick if a
        // matching window shows up.
        guard let windowFrame = findWindowFrame(for: table) else {
            Log.hud.debug("Skipping panel creation for '\(table.tableName, privacy: .public)' — no matching PokerStars window")
            return
        }

        let heroSeat = findHeroSeat(in: table)
        let maxSeats = table.tableSize <= 6 ? 6 : 9
        let tableSize = table.tableSize

        for seat in table.seatAssignments {
            guard let playerName = seat.playerName, !playerName.isEmpty else { continue }

            let key = PanelKey(tableId: table.id, seatNumber: seat.seatNumber)
            guard panels[key] == nil else { continue }

            // Calculate visual slot (counter-clockwise from hero)
            // PokerStars: hero at bottom, seat+1 = left, seat+2 = top-left, etc.
            // Slot 0=hero(bottom), 1=left, 2=top-left, 3=top, 4=top-right, 5=right
            let slot = (seat.seatNumber - heroSeat + maxSeats) % maxSeats
            panelSlots[key] = slot

            // Get position: user-saved offset for this (tableSize, slot), or default
            let fractionalOffset = HUDSeatOffsets.shared.offset(forTableSize: tableSize, slot: slot)
                ?? HUDSeatOffsets.defaultOffset(forTableSize: tableSize, slot: slot)

            let position = HUDSeatOffsets.shared.fractionalToAbsolute(fractionalOffset, windowFrame: windowFrame)

            let panelRect = NSRect(x: position.x, y: position.y, width: 180, height: 90)
            let panel = HUDPanel(contentRect: panelRect)
            panel.slotIndex = slot

            // Set up drag callback to save position. Capture tableId and
            // tableSize at creation time so the saved offset lands in the
            // correct (tableSize, slot) bucket even if the table is later
            // resized or rebound to a different window.
            let tableId = table.id
            let capturedTableSize = tableSize
            panel.onDragEnd = { [weak self] newOrigin in
                guard let self = self else { return }
                // Find the window frame this table is bound to
                let windows = PokerStarsWindowDetector.findTableWindows()
                var windowFrame: NSRect?

                if let boundID = self.tableWindowBinding[tableId],
                   let w = windows.first(where: { $0.windowID == boundID }) {
                    windowFrame = w.frame
                } else if let w = windows.first {
                    // Fallback to any PokerStars window
                    windowFrame = w.frame
                }

                if let wf = windowFrame {
                    let fraction = HUDSeatOffsets.shared.absoluteToFractional(newOrigin, windowFrame: wf)
                    HUDSeatOffsets.shared.saveOffset(fraction, forTableSize: capturedTableSize, slot: slot)
                    let fx = String(format: "%.3f", fraction.x)
                    let fy = String(format: "%.3f", fraction.y)
                    Log.hud.debug("Saved \(capturedTableSize)-max slot \(slot) at (\(fx, privacy: .public), \(fy, privacy: .public))")
                } else {
                    Log.hud.warning("No window found to save \(capturedTableSize)-max slot \(slot)")
                }
            }

            let stats = playerStats[playerName]
            let state = HUDPanelState(stats: stats)
            panelStates[key] = state
            var view = HUDContentView(playerName: playerName, state: state, configuration: configuration)
            // Resize the panel when the user double-clicks to
            // expand / collapse the stat grid.
            view.onExpandToggle = { [weak panel] expanded in
                panel?.resize(to: expanded
                    ? CGSize(width: 210, height: 420)
                    : CGSize(width: 180, height: 90))
            }
            panel.setContent(view)
            panel.orderFront(nil)
            panels[key] = panel
        }
    }

    // MARK: - Position Tracking

    private func startPositionTracking() {
        guard positionTimer == nil else { return }
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.repositionAllPanels()
            }
        }
    }

    private func stopPositionTracking() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    /// Cached last window frames to detect when the poker window actually moved
    private var lastWindowFrames: [UUID: NSRect] = [:]

    /// Per-table fingerprint of the last `findWindowFrame` call result, used
    /// to rate-limit the diagnostic log so we only print on state changes
    /// (a 500 ms reposition tick happens 120× per minute and would otherwise
    /// flood the console).
    private var lastFindWindowLog: [UUID: String] = [:]

    private func repositionAllPanels() {
        // Get ALL PokerStars table windows in front-to-back z-order.
        // CGWindowListCopyWindowInfo returns them in this order, so
        // windows[0] is the frontmost table.
        let allWindows = PokerStarsWindowDetector.findTableWindows()
        let frontmostWindowID = allWindows.first?.windowID

        for table in trackedTables {
            guard let windowFrame = findWindowFrame(for: table) else { continue }

            let boundID = tableWindowBinding[table.id]

            // Only show panels for the frontmost PokerStars table.
            // Cross-app window ordering via NSWindow.order(_:relativeTo:)
            // doesn't work (Apple restricts it to same-app windows),
            // so the only reliable way to prevent background table
            // labels from bleeding through onto the front table is
            // to hide them entirely. When the user clicks a different
            // table to bring it forward, CGWindowList's ordering
            // updates and the next 500ms tick swaps which panels are
            // visible.
            let isFrontmostTable = (boundID != nil && boundID == frontmostWindowID)

            for seat in table.seatAssignments {
                let key = PanelKey(tableId: table.id, seatNumber: seat.seatNumber)
                guard let panel = panels[key] else { continue }

                if !isFrontmostTable {
                    panel.orderOut(nil)
                    continue
                }

                // Only reposition if the poker window actually moved
                let needsReposition: Bool
                if let lastFrame = lastWindowFrames[table.id] {
                    let wdx = abs(windowFrame.origin.x - lastFrame.origin.x)
                    let wdy = abs(windowFrame.origin.y - lastFrame.origin.y)
                    let wdw = abs(windowFrame.width - lastFrame.width)
                    let wdh = abs(windowFrame.height - lastFrame.height)
                    needsReposition = wdx > 2 || wdy > 2 || wdw > 2 || wdh > 2
                } else {
                    needsReposition = true
                }

                if let slot = panelSlots[key] {
                    if needsReposition {
                        let fractionalOffset = HUDSeatOffsets.shared.offset(forTableSize: table.tableSize, slot: slot)
                            ?? HUDSeatOffsets.defaultOffset(forTableSize: table.tableSize, slot: slot)
                        let targetPos = HUDSeatOffsets.shared.fractionalToAbsolute(fractionalOffset, windowFrame: windowFrame)
                        panel.reposition(to: targetPos)
                    }
                    panel.orderFront(nil)
                }
            }

            if isFrontmostTable || lastWindowFrames[table.id] == nil {
                lastWindowFrames[table.id] = windowFrame
            }
        }
    }

    // MARK: - Window Detection

    private func findWindowFrame(for table: ActiveTable) -> NSRect? {
        let windows = PokerStarsWindowDetector.findTableWindows()
        guard !windows.isEmpty else {
            logFindWindow(for: table, windows: [], step: "no-windows", boundID: nil)
            return nil
        }

        // 1. If we have a cached binding, use it — but if window titles are
        //    readable (Screen Recording or Accessibility granted) and the
        //    cached window's title does NOT contain this table's name,
        //    treat the cache as poisoned and re-match. This is what auto-
        //    corrects the multi-table launch swap that happens when
        //    `autoManageTables` had to bind by exclusion: as soon as titles
        //    become readable on the next reposition tick (every 500 ms),
        //    we notice the mismatch and fix it without an app relaunch.
        if let boundID = tableWindowBinding[table.id],
           let bound = windows.first(where: { $0.windowID == boundID }) {
            if bound.windowName.isEmpty {
                // No title to validate against — trust the cached binding.
                logFindWindow(for: table, windows: windows, step: "1-cached-no-title", boundID: boundID)
                return bound.frame
            }
            if bound.windowName.contains(table.tableName) {
                // Cached binding is correct.
                logFindWindow(for: table, windows: windows, step: "1-cached-validated", boundID: boundID)
                return bound.frame
            }
            // Cached binding is wrong. Clear it and fall through to step 2.
            Log.hud.debug("Cached binding for '\(table.tableName, privacy: .public)' points at window titled '\(bound.windowName, privacy: .public)' — mismatch, re-binding")
            tableWindowBinding.removeValue(forKey: table.id)
        }

        // 2. Match by window title (works whenever Screen Recording OR
        //    Accessibility permission is granted — see PokerStarsWindowDetector
        //    .enrichWithAXTitles).
        if let matched = windows.first(where: { !$0.windowName.isEmpty && $0.windowName.contains(table.tableName) }) {
            tableWindowBinding[table.id] = matched.windowID
            Log.hud.debug("Bound '\(table.tableName, privacy: .public)' to window \(matched.windowID) by name match")
            logFindWindow(for: table, windows: windows, step: "2-name-match", boundID: matched.windowID)
            return matched.frame
        }

        // 3. Title-less fallback: bind by exclusion to the first unbound
        //    window. CGWindowList returns windows front-to-back, so the
        //    frontmost unbound window is usually the right one for a
        //    single-table session. With multiple unbound windows this is
        //    inherently ambiguous (the long-standing multi-table launch
        //    bug), but it's better to bind *something* than to leave the
        //    HUD invisible — and step 1's cache validation will auto-
        //    correct on the next tick if the user grants Accessibility
        //    permission and titles become readable.
        let boundIDs = Set(tableWindowBinding.values)
        let unboundWindows = windows.filter { !boundIDs.contains($0.windowID) }

        if let window = unboundWindows.first {
            tableWindowBinding[table.id] = window.windowID
            if unboundWindows.count > 1 {
                Log.hud.warning("Bound '\(table.tableName, privacy: .public)' to window \(window.windowID) but \(unboundWindows.count) windows are unbound and titles are unreadable — grant Accessibility permission in System Settings → Privacy & Security for reliable multi-table binding.")
            } else {
                Log.hud.debug("Bound '\(table.tableName, privacy: .public)' to only unbound window \(window.windowID)")
            }
            logFindWindow(for: table, windows: windows, step: "3-exclusion-fallback", boundID: window.windowID)
            return window.frame
        }

        // 4. All windows are bound. Our binding's CGWindowID no longer
        //    exists (window was closed and reopened, etc.). Clear the
        //    stale binding so the next call falls through to step 2 or 3.
        tableWindowBinding.removeValue(forKey: table.id)
        if let front = windows.first {
            tableWindowBinding[table.id] = front.windowID
            logFindWindow(for: table, windows: windows, step: "4-stale-cleared", boundID: front.windowID)
            return front.frame
        }

        logFindWindow(for: table, windows: windows, step: "no-window", boundID: nil)
        return nil
    }

    /// Rate-limited diagnostic log for `findWindowFrame`. Only prints when
    /// the (step, boundID, AX-permission, window-list-fingerprint) tuple
    /// changes for this table — so a stable correct binding doesn't spam
    /// the console at 2 Hz, but a flapping or stuck mis-binding gets a
    /// fresh log line every time the situation changes. Designed so we can
    /// ask the user to paste the console and immediately see what state
    /// `findWindowFrame` is in.
    private func logFindWindow(
        for table: ActiveTable,
        windows: [DetectedPokerWindow],
        step: String,
        boundID: CGWindowID?
    ) {
        let axGranted = AccessibilityPermission.isGranted
        let windowFingerprint = windows
            .map { "\($0.windowID):\($0.windowName.isEmpty ? "<no-title>" : String($0.windowName.prefix(40)))" }
            .joined(separator: " | ")
        let fingerprint = "\(step)|\(boundID.map { String($0) } ?? "nil")|ax=\(axGranted)|\(windowFingerprint)"
        if lastFindWindowLog[table.id] == fingerprint { return }
        lastFindWindowLog[table.id] = fingerprint
        let boundStr = boundID.map { String($0) } ?? "nil"
        Log.hud.debug("[diag] '\(table.tableName, privacy: .public)' → step=\(step, privacy: .public) bound=\(boundStr, privacy: .public) axGranted=\(axGranted) windows=[\(windowFingerprint, privacy: .public)]")
    }

    /// Rebind a table to a specific window
    func bindTable(_ tableId: UUID, toWindow windowID: CGWindowID) {
        tableWindowBinding[tableId] = windowID
    }

    /// Get all currently bound window IDs
    func getAllBoundWindowIDs() -> [CGWindowID] {
        Array(tableWindowBinding.values)
    }

    /// Returns the cached window binding for a specific table, or nil if
    /// none. Used by `AppState.pruneClosedTables()` as the title-less
    /// fallback check when a table's PokerStars window title can't be
    /// matched (no Screen Recording / Accessibility permission).
    func boundWindowID(for tableId: UUID) -> CGWindowID? {
        tableWindowBinding[tableId]
    }

    /// Manual recovery action: clear every cached table → window binding so
    /// the next reposition tick re-binds every tracked table from scratch.
    /// Wired to the menu-bar "Reset HUD Bindings" item for users who hit a
    /// stuck multi-table swap mid-session and don't want to relaunch the
    /// app. Also clears `lastWindowFrames` so the next tick is treated as
    /// "first observation" and forces a layout pass on every panel.
    func resetAllBindings() {
        let count = tableWindowBinding.count
        tableWindowBinding.removeAll()
        lastWindowFrames.removeAll()
        // Drop the per-table diagnostic fingerprints too so the next
        // re-bind cycle logs fresh state to Console.app — useful for
        // diagnosing whether the manual reset actually fixed anything.
        lastFindWindowLog.removeAll()
        Log.hud.debug("Reset \(count) cached table-window binding(s); next reposition tick will re-bind from scratch")
    }

    private func findHeroSeat(in table: ActiveTable) -> Int {
        do {
            let row = try DatabaseManager.shared.reader.read { db in
                try Row.fetchOne(db, sql: """
                    SELECT hp.seat FROM hand_players hp
                    INNER JOIN hands h ON h.id = hp.handId
                    WHERE h.tableName = ? AND hp.isHero = 1
                    ORDER BY h.playedAt DESC LIMIT 1
                """, arguments: [table.tableName])
            }
            let seat: Int? = row?["seat"]
            return seat ?? 1
        } catch {
            return 1
        }
    }

    // MARK: - Single Panel

    func removeSinglePanel(key: PanelKey) {
        if let panel = panels.removeValue(forKey: key) {
            panel.orderOut(nil)
            panel.close()
        }
        panelSlots.removeValue(forKey: key)
        panelStates.removeValue(forKey: key)
    }

    // MARK: - Hide

    func hideHUD(for table: ActiveTable) {
        for seat in table.seatAssignments {
            let key = PanelKey(tableId: table.id, seatNumber: seat.seatNumber)
            removeSinglePanel(key: key)
        }
        trackedTables.removeAll { $0.id == table.id }
        tableWindowBinding.removeValue(forKey: table.id)
        if trackedTables.isEmpty { stopPositionTracking() }
    }

    func hideAll() {
        for (_, panel) in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        panelSlots.removeAll()
        panelStates.removeAll()
        trackedTables.removeAll()
        tableWindowBinding.removeAll()
        stopPositionTracking()
    }

    // MARK: - Stats Refresh

    func refreshStats(for playerNames: [String], tables: [ActiveTable]) {
        let statsRepo = StatsRepository()
        let playerRepo = PlayerRepository()

        for playerName in playerNames {
            if let player = try? playerRepo.fetchByUsername(playerName, siteId: nil),
               let playerId = player.id,
               let stats = try? statsRepo.fetchPlayerStats(playerId: playerId) {
                playerStats[playerName] = stats
            }
        }
        updatePanels(for: playerNames, tables: tables)
    }

    /// Push the latest `playerStats` into the `HUDPanelState` objects for
    /// any seat on `tables` whose player name is in `playerNames`. This is
    /// the only path that should trigger the flash-border animation, so we
    /// stamp `lastUpdated = Date()` on every mutated state.
    ///
    /// Does NOT call `HUDPanel.setContent` — the content view was installed
    /// once in `createPanels` and observes its state object. That is what
    /// keeps the flash animation alive across refreshes.
    private func updatePanels(for playerNames: [String], tables: [ActiveTable]) {
        let now = Date()
        for table in tables {
            for seat in table.seatAssignments {
                guard let playerName = seat.playerName, playerNames.contains(playerName) else { continue }
                let key = PanelKey(tableId: table.id, seatNumber: seat.seatNumber)
                guard let state = panelStates[key] else { continue }

                state.stats = playerStats[playerName]
                state.lastUpdated = now
            }
        }
    }

    func refreshAllStats(tables: [ActiveTable]) {
        let allPlayers = Set(tables.flatMap { $0.seatAssignments.compactMap { $0.playerName } })
        refreshStats(for: Array(allPlayers), tables: tables)
    }

    /// Refresh stats for players affected by an import. Uses `trackedTables`
    /// as the scope, which is what the HUDManager itself has been told to
    /// show — no need for the caller to pass a tables list.
    func handleNewHands(result: HUDImportResult) {
        let affectedPlayers = Array(result.affectedPlayerNames)
        guard !affectedPlayers.isEmpty else { return }
        refreshStats(for: affectedPlayers, tables: trackedTables)
    }

    func updateConfiguration(_ config: HUDConfiguration, tables: [ActiveTable]) {
        self.configuration = config
        refreshAllStats(tables: tables)
    }
}
