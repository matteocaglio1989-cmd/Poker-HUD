import AppKit
import SwiftUI
import GRDB

/// Manages all HUD overlay panels — creates, positions, refreshes, and destroys them.
/// Panel positions are stored as fractional offsets relative to the poker table window,
/// so they work across any window size and position.
@MainActor
class HUDManager {
    private var panels: [PanelKey: HUDPanel] = [:]
    private var playerStats: [String: PlayerStats] = [:]
    private var configuration: HUDConfiguration
    private var positionTimer: Timer?
    private var trackedTables: [ActiveTable] = []
    private var tableWindowBinding: [UUID: CGWindowID] = [:]
    /// Maps PanelKey -> slot index (hero-relative position)
    private var panelSlots: [PanelKey: Int] = [:]

    init(configuration: HUDConfiguration = .standard) {
        self.configuration = configuration
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
        let defaults = table.tableSize <= 6 ? HUDSeatOffsets.default6Max : HUDSeatOffsets.default9Max

        for seat in table.seatAssignments {
            guard let playerName = seat.playerName, !playerName.isEmpty else { continue }

            let key = PanelKey(tableId: table.id, seatNumber: seat.seatNumber)
            guard panels[key] == nil else { continue }

            // Calculate visual slot (counter-clockwise from hero)
            // PokerStars: hero at bottom, seat+1 = left, seat+2 = top-left, etc.
            // Slot 0=hero(bottom), 1=left, 2=top-left, 3=top, 4=top-right, 5=right
            let slot = (seat.seatNumber - heroSeat + maxSeats) % maxSeats
            panelSlots[key] = slot

            // Get position: user-saved offset, or default
            let fractionalOffset = HUDSeatOffsets.shared.offset(forSlot: slot) ?? defaults[slot] ?? CGPoint(x: 0.5, y: 0.5)

            let position: CGPoint
            if let wf = windowFrame {
                position = HUDSeatOffsets.shared.fractionalToAbsolute(fractionalOffset, windowFrame: wf)
                print("[HUD] Panel \(playerName) slot=\(slot) using saved offset, window=\(Int(wf.width))x\(Int(wf.height))")
            } else {
                // No window found — use saved offsets relative to screen as fallback
                let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
                position = HUDSeatOffsets.shared.fractionalToAbsolute(fractionalOffset, windowFrame: screen)
                print("[HUD] Panel \(playerName) slot=\(slot) NO WINDOW FOUND, using screen fallback")
            }

            let panelRect = NSRect(x: position.x, y: position.y, width: 180, height: 90)
            let panel = HUDPanel(contentRect: panelRect)
            panel.slotIndex = slot

            // Set up drag callback to save position
            let tableId = table.id
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
                    HUDSeatOffsets.shared.saveOffset(fraction, forSlot: slot)
                    print("[HUD] Saved slot \(slot) at (\(String(format: "%.3f", fraction.x)), \(String(format: "%.3f", fraction.y)))")
                } else {
                    print("[HUD] WARNING: No window found to save slot \(slot)")
                }
            }

            let stats = playerStats[playerName]
            let view = HUDContentView(playerName: playerName, stats: stats, configuration: configuration)
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

            let defaults = table.tableSize <= 6 ? HUDSeatOffsets.default6Max : HUDSeatOffsets.default9Max

            for seat in table.seatAssignments {
                let key = PanelKey(tableId: table.id, seatNumber: seat.seatNumber)
                guard let panel = panels[key],
                      let slot = panelSlots[key] else { continue }

                let fractionalOffset = HUDSeatOffsets.shared.offset(forSlot: slot) ?? defaults[slot] ?? CGPoint(x: 0.5, y: 0.5)
                let targetPos = HUDSeatOffsets.shared.fractionalToAbsolute(fractionalOffset, windowFrame: windowFrame)

                panel.reposition(to: targetPos)
            }
        }
    }

    // MARK: - Window Detection

    private func findWindowFrame(for table: ActiveTable) -> NSRect? {
        let windows = PokerStarsWindowDetector.findTableWindows()
        guard !windows.isEmpty else { return nil }

        // 1. Use existing binding if window still exists
        if let boundID = tableWindowBinding[table.id],
           let w = windows.first(where: { $0.windowID == boundID }) {
            return w.frame
        }

        // 2. Match by extracted table name (AppleScript provides clean table names)
        if let matched = windows.first(where: { $0.tableName == table.tableName }) {
            tableWindowBinding[table.id] = matched.windowID
            print("[HUD] Bound '\(table.tableName)' to window by exact table name match")
            return matched.frame
        }

        // 3. Try partial match on window title
        if let matched = windows.first(where: { $0.windowName.contains(table.tableName) }) {
            tableWindowBinding[table.id] = matched.windowID
            print("[HUD] Bound '\(table.tableName)' to window by partial name match")
            return matched.frame
        }

        // 4. No match found — table window might not be open yet
        print("[HUD] No window found for '\(table.tableName)'")

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

    /// Swap window bindings between two tables
    func swapBindings(tableId1: UUID, tableId2: UUID) {
        let wid1 = tableWindowBinding[tableId1]
        let wid2 = tableWindowBinding[tableId2]
        if let w1 = wid1 { tableWindowBinding[tableId2] = w1 }
        if let w2 = wid2 { tableWindowBinding[tableId1] = w2 }
        lastWindowFrames.removeAll()
        print("[HUD] Swapped bindings: \(tableId1) <-> \(tableId2)")
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

    private func updatePanels(for playerNames: [String], tables: [ActiveTable]) {
        for table in tables {
            for seat in table.seatAssignments {
                guard let playerName = seat.playerName, playerNames.contains(playerName) else { continue }
                let key = PanelKey(tableId: table.id, seatNumber: seat.seatNumber)
                guard let panel = panels[key] else { continue }

                let stats = playerStats[playerName]
                let view = HUDContentView(playerName: playerName, stats: stats, configuration: configuration)
                panel.setContent(view)
            }
        }
    }

    func refreshAllStats(tables: [ActiveTable]) {
        let allPlayers = Set(tables.flatMap { $0.seatAssignments.compactMap { $0.playerName } })
        refreshStats(for: Array(allPlayers), tables: tables)
    }

    func handleNewHands(result: HUDImportResult, tables: [ActiveTable]) {
        let affectedPlayers = Array(result.affectedPlayerNames)
        guard !affectedPlayers.isEmpty else { return }
        refreshStats(for: affectedPlayers, tables: tables)
    }

    func updateConfiguration(_ config: HUDConfiguration, tables: [ActiveTable]) {
        self.configuration = config
        refreshAllStats(tables: tables)
    }
}
