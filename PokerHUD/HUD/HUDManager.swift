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

    init(configuration: HUDConfiguration = .standard) {
        self.configuration = configuration
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
                print("[HUD] Error loading \(playerName): \(error)")
            }
        }

        createPanels(for: table)

        if !trackedTables.contains(where: { $0.id == table.id }) {
            trackedTables.append(table)
        }
        startPositionTracking()
    }

    private func createPanels(for table: ActiveTable) {
        let windowFrame = findWindowFrame(for: table)
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

            let position: CGPoint
            if let wf = windowFrame {
                position = HUDSeatOffsets.shared.fractionalToAbsolute(fractionalOffset, windowFrame: wf)
            } else {
                let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
                position = CGPoint(x: screen.midX - 90 + CGFloat(slot) * 40, y: screen.midY)
            }

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
                    print("[HUD] Saved \(capturedTableSize)-max slot \(slot) at (\(String(format: "%.3f", fraction.x)), \(String(format: "%.3f", fraction.y)))")
                } else {
                    print("[HUD] WARNING: No window found to save \(capturedTableSize)-max slot \(slot)")
                }
            }

            let stats = playerStats[playerName]
            let state = HUDPanelState(stats: stats)
            panelStates[key] = state
            let view = HUDContentView(playerName: playerName, state: state, configuration: configuration)
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

    private func repositionAllPanels() {
        for table in trackedTables {
            guard let windowFrame = findWindowFrame(for: table) else { continue }

            // Only reposition if the poker window itself moved (not the user dragging HUD panels)
            if let lastFrame = lastWindowFrames[table.id] {
                let wdx = abs(windowFrame.origin.x - lastFrame.origin.x)
                let wdy = abs(windowFrame.origin.y - lastFrame.origin.y)
                let wdw = abs(windowFrame.width - lastFrame.width)
                let wdh = abs(windowFrame.height - lastFrame.height)
                guard wdx > 2 || wdy > 2 || wdw > 2 || wdh > 2 else { continue }
            }
            lastWindowFrames[table.id] = windowFrame

            let tableSize = table.tableSize

            for seat in table.seatAssignments {
                let key = PanelKey(tableId: table.id, seatNumber: seat.seatNumber)
                guard let panel = panels[key],
                      let slot = panelSlots[key] else { continue }

                let fractionalOffset = HUDSeatOffsets.shared.offset(forTableSize: tableSize, slot: slot)
                    ?? HUDSeatOffsets.defaultOffset(forTableSize: tableSize, slot: slot)
                let targetPos = HUDSeatOffsets.shared.fractionalToAbsolute(fractionalOffset, windowFrame: windowFrame)

                panel.reposition(to: targetPos)
            }
        }
    }

    // MARK: - Window Detection

    private func findWindowFrame(for table: ActiveTable) -> NSRect? {
        let windows = PokerStarsWindowDetector.findTableWindows()
        guard !windows.isEmpty else { return nil }

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
                return bound.frame
            }
            if bound.windowName.contains(table.tableName) {
                // Cached binding is correct.
                return bound.frame
            }
            // Cached binding is wrong. Clear it and fall through to step 2.
            print("[HUD] Cached binding for '\(table.tableName)' points at window titled '\(bound.windowName)' — mismatch, re-binding")
            tableWindowBinding.removeValue(forKey: table.id)
        }

        // 2. Match by window title (works whenever Screen Recording OR
        //    Accessibility permission is granted — see PokerStarsWindowDetector
        //    .enrichWithAXTitles).
        if let matched = windows.first(where: { !$0.windowName.isEmpty && $0.windowName.contains(table.tableName) }) {
            tableWindowBinding[table.id] = matched.windowID
            print("[HUD] Bound '\(table.tableName)' to window \(matched.windowID) by name match")
            return matched.frame
        }

        // 3. Title-less fallback. Only safe to bind by exclusion when there
        //    is EXACTLY ONE unbound window — otherwise we'd be guessing and
        //    risk swapping bindings (the multi-table launch bug). When the
        //    fallback is unsafe, return nil and let the next reposition
        //    tick retry; the user should grant Accessibility permission so
        //    the title-based path in step 2 starts working.
        let boundIDs = Set(tableWindowBinding.values)
        let unboundWindows = windows.filter { !boundIDs.contains($0.windowID) }

        if unboundWindows.count == 1 {
            let window = unboundWindows[0]
            tableWindowBinding[table.id] = window.windowID
            print("[HUD] Bound '\(table.tableName)' to only unbound window \(window.windowID)")
            return window.frame
        }

        if unboundWindows.count > 1 {
            print("[HUD] WARNING: cannot uniquely bind '\(table.tableName)' — \(unboundWindows.count) unbound PokerStars windows and no readable titles. Grant Accessibility permission in System Settings → Privacy & Security to enable title-based binding.")
        }

        return nil
    }

    /// Rebind a table to a specific window
    func bindTable(_ tableId: UUID, toWindow windowID: CGWindowID) {
        tableWindowBinding[tableId] = windowID
    }

    /// Get all currently bound window IDs
    func getAllBoundWindowIDs() -> [CGWindowID] {
        Array(tableWindowBinding.values)
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
