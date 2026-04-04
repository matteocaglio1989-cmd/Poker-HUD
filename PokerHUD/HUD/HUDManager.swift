import AppKit
import SwiftUI

/// Manages all HUD overlay panels — creates, positions, refreshes, and destroys them
@MainActor
class HUDManager {
    private var panels: [PanelKey: HUDPanel] = [:]
    private var playerStats: [String: PlayerStats] = [:] // playerName -> stats cache
    private let statsRepository: StatsRepository
    private let playerRepository: PlayerRepository
    private var configuration: HUDConfiguration

    init(
        statsRepository: StatsRepository = StatsRepository(),
        playerRepository: PlayerRepository = PlayerRepository(),
        configuration: HUDConfiguration = .standard
    ) {
        self.statsRepository = statsRepository
        self.playerRepository = playerRepository
        self.configuration = configuration
    }

    // MARK: - Panel Lifecycle

    /// Show HUD panels for all assigned seats on a table
    func showHUD(for table: ActiveTable) {
        for seat in table.seatAssignments {
            guard let playerName = seat.playerName, !playerName.isEmpty else { continue }

            let key = PanelKey(tableId: table.id, seatNumber: seat.seatNumber)
            guard panels[key] == nil else { continue } // Already showing

            let panelRect = NSRect(
                x: table.origin.x + seat.offset.x,
                y: table.origin.y + seat.offset.y,
                width: 180,
                height: 100
            )

            let panel = HUDPanel(contentRect: panelRect)
            let stats = playerStats[playerName]
            let view = HUDContentView(
                playerName: playerName,
                stats: stats,
                configuration: configuration
            )
            panel.setContent(view)
            panel.orderFront(nil)
            panels[key] = panel
        }
    }

    /// Hide all HUD panels for a table
    func hideHUD(for table: ActiveTable) {
        for seat in table.seatAssignments {
            let key = PanelKey(tableId: table.id, seatNumber: seat.seatNumber)
            if let panel = panels.removeValue(forKey: key) {
                panel.orderOut(nil)
                panel.close()
            }
        }
    }

    /// Hide all panels
    func hideAll() {
        for (_, panel) in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
    }

    // MARK: - Stats Refresh

    /// Refresh stats for specific players and update their panels
    func refreshStats(for playerNames: [String], tables: [ActiveTable]) {
        Task {
            // Fetch stats off the main thread
            let fetchedStats = await Task.detached { [statsRepository, playerRepository] in
                var results: [String: PlayerStats] = [:]
                for playerName in playerNames {
                    if let player = try? playerRepository.fetchByUsername(playerName, siteId: nil),
                       let playerId = player.id,
                       let stats = try? statsRepository.fetchPlayerStats(playerId: playerId) {
                        results[playerName] = stats
                    }
                }
                return results
            }.value

            // Update cache and panels on MainActor
            for (name, stats) in fetchedStats {
                playerStats[name] = stats
            }
            updatePanels(for: playerNames, tables: tables)
        }
    }

    /// Update panel content for given players (must be called on MainActor)
    private func updatePanels(for playerNames: [String], tables: [ActiveTable]) {
        for table in tables {
            for seat in table.seatAssignments {
                guard let playerName = seat.playerName, playerNames.contains(playerName) else { continue }
                let key = PanelKey(tableId: table.id, seatNumber: seat.seatNumber)
                guard let panel = panels[key] else { continue }

                let stats = playerStats[playerName]
                let view = HUDContentView(
                    playerName: playerName,
                    stats: stats,
                    configuration: configuration
                )
                panel.setContent(view)
            }
        }
    }

    /// Refresh all stats for all visible panels
    func refreshAllStats(tables: [ActiveTable]) {
        let allPlayers = Set(tables.flatMap { $0.seatAssignments.compactMap { $0.playerName } })
        refreshStats(for: Array(allPlayers), tables: tables)
    }

    /// Handle new hands imported — selectively refresh affected panels
    func handleNewHands(result: HUDImportResult, tables: [ActiveTable]) {
        let affectedPlayers = Array(result.affectedPlayerNames)
        guard !affectedPlayers.isEmpty else { return }
        refreshStats(for: affectedPlayers, tables: tables)
    }

    /// Update HUD configuration
    func updateConfiguration(_ config: HUDConfiguration, tables: [ActiveTable]) {
        self.configuration = config
        refreshAllStats(tables: tables)
    }

}
