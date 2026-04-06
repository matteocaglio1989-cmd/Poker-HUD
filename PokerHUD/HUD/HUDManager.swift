import AppKit
import SwiftUI
import GRDB

/// Manages all HUD overlay panels.
/// Each table is matched to its PokerStars window by TABLE NAME (via osascript).
@MainActor
class HUDManager {
    private var panels: [PanelKey: HUDPanel] = [:]
    private var playerStats: [String: PlayerStats] = [:]
    private var configuration: HUDConfiguration
    private var positionTimer: Timer?
    private var trackedTables: [ActiveTable] = []
    private var panelSlots: [PanelKey: Int] = [:]
    private var lastWindowFrames: [String: NSRect] = [:] // tableName -> last known frame

    init(configuration: HUDConfiguration = .standard) {
        self.configuration = configuration
    }

    // MARK: - Show HUD

    func showHUD(for table: ActiveTable) {
        let playerNames = table.seatAssignments.compactMap { $0.playerName }.filter { !$0.isEmpty }
        guard !playerNames.isEmpty else { return }

        // Load stats
        let statsRepo = StatsRepository()
        let playerRepo = PlayerRepository()
        for playerName in playerNames {
            if let player = try? playerRepo.fetchByUsername(playerName, siteId: nil),
               let playerId = player.id,
               let stats = try? statsRepo.fetchPlayerStats(playerId: playerId) {
                playerStats[playerName] = stats
            }
        }

        createPanels(for: table)

        if !trackedTables.contains(where: { $0.id == table.id }) {
            trackedTables.append(table)
        }
        startPositionTracking()
    }

    // MARK: - Create Panels

    private func createPanels(for table: ActiveTable) {
        // Find THIS table's window by name
        let windowFrame = PokerStarsWindowDetector.shared.window(forTable: table.tableName)?.frame
        let heroSeat = findHeroSeat(in: table)
        let maxSeats = table.tableSize <= 6 ? 6 : 9
        let defaults = table.tableSize <= 6 ? HUDSeatOffsets.default6Max : HUDSeatOffsets.default9Max

        for seat in table.seatAssignments {
            guard let playerName = seat.playerName, !playerName.isEmpty else { continue }

            let key = PanelKey(tableId: table.id, seatNumber: seat.seatNumber)
            guard panels[key] == nil else { continue }

            let slot = (seat.seatNumber - heroSeat + maxSeats) % maxSeats
            panelSlots[key] = slot

            let fractionalOffset = HUDSeatOffsets.shared.offset(forSlot: slot) ?? defaults[slot] ?? CGPoint(x: 0.5, y: 0.5)

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

            // Save position on drag — use THIS table's window frame
            let tableName = table.tableName
            panel.onDragEnd = { newOrigin in
                if let wf = PokerStarsWindowDetector.shared.window(forTable: tableName)?.frame {
                    let fraction = HUDSeatOffsets.shared.absoluteToFractional(newOrigin, windowFrame: wf)
                    HUDSeatOffsets.shared.saveOffset(fraction, forSlot: slot)
                }
            }

            let stats = playerStats[playerName]
            let view = HUDContentView(playerName: playerName, stats: stats, configuration: configuration)
            panel.setContent(view)
            panel.orderFront(nil)
            panels[key] = panel
        }
    }

    // MARK: - Position Tracking (follow window when moved)

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

    private func repositionAllPanels() {
        let defaults6 = HUDSeatOffsets.default6Max
        let defaults9 = HUDSeatOffsets.default9Max

        for table in trackedTables {
            // Find this table's window BY NAME
            guard let windowFrame = PokerStarsWindowDetector.shared.window(forTable: table.tableName)?.frame else { continue }

            // Only reposition if window actually moved
            if let lastFrame = lastWindowFrames[table.tableName] {
                let dx = abs(windowFrame.origin.x - lastFrame.origin.x)
                let dy = abs(windowFrame.origin.y - lastFrame.origin.y)
                let dw = abs(windowFrame.width - lastFrame.width)
                let dh = abs(windowFrame.height - lastFrame.height)
                guard dx > 2 || dy > 2 || dw > 2 || dh > 2 else { continue }
            }
            lastWindowFrames[table.tableName] = windowFrame

            let defaults = table.tableSize <= 6 ? defaults6 : defaults9

            for seat in table.seatAssignments {
                let key = PanelKey(tableId: table.id, seatNumber: seat.seatNumber)
                guard let panel = panels[key], let slot = panelSlots[key] else { continue }

                let fractionalOffset = HUDSeatOffsets.shared.offset(forSlot: slot) ?? defaults[slot] ?? CGPoint(x: 0.5, y: 0.5)
                let targetPos = HUDSeatOffsets.shared.fractionalToAbsolute(fractionalOffset, windowFrame: windowFrame)
                panel.reposition(to: targetPos)
            }
        }
    }

    // MARK: - Hero Seat

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

    // MARK: - Panel Management

    func removeSinglePanel(key: PanelKey) {
        if let panel = panels.removeValue(forKey: key) {
            panel.orderOut(nil)
            panel.close()
        }
        panelSlots.removeValue(forKey: key)
    }

    func hideHUD(for table: ActiveTable) {
        for seat in table.seatAssignments {
            removeSinglePanel(key: PanelKey(tableId: table.id, seatNumber: seat.seatNumber))
        }
        trackedTables.removeAll { $0.id == table.id }
        lastWindowFrames.removeValue(forKey: table.tableName)
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
        lastWindowFrames.removeAll()
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
