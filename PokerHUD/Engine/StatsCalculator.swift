import Foundation

/// Calculates poker statistics from parsed hand data
class StatsCalculator {
    private let databaseManager: DatabaseManager
    private let statsRepository: StatsRepository

    init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
        self.statsRepository = StatsRepository(databaseManager: databaseManager)
    }

    /// Calculate stats for parsed players based on their actions
    /// - Parameters:
    ///   - players: Array of player data
    ///   - actions: Array of actions for the hand
    /// - Returns: Updated players with calculated stats
    func calculateHandStats(players: [PlayerData], actions: [ActionData]) -> [PlayerData] {
        var updatedPlayers = players

        // Group actions by player and street
        var playerActions: [String: [String: [ActionData]]] = [:]
        for action in actions {
            if playerActions[action.username] == nil {
                playerActions[action.username] = [:]
            }
            if playerActions[action.username]![action.street] == nil {
                playerActions[action.username]![action.street] = []
            }
            playerActions[action.username]![action.street]!.append(action)
        }

        // Get preflop actions
        let preflopActions = actions.filter { $0.street == "PREFLOP" }

        // Determine who was the initial raiser (for VPIP/PFR)
        var firstRaiseUsername: String? = nil
        var secondRaiseUsername: String? = nil
        var thirdRaiseUsername: String? = nil

        for action in preflopActions {
            if action.actionType == "RAISE" || action.actionType == "BET" {
                if firstRaiseUsername == nil {
                    firstRaiseUsername = action.username
                } else if secondRaiseUsername == nil {
                    secondRaiseUsername = action.username
                } else if thirdRaiseUsername == nil {
                    thirdRaiseUsername = action.username
                }
            }
        }

        // Calculate stats for each player
        for i in 0..<updatedPlayers.count {
            let username = updatedPlayers[i].username
            let actions = playerActions[username] ?? [:]
            let preflopPlayerActions = actions["PREFLOP"] ?? []

            // VPIP: Did player voluntarily put money in pot preflop?
            // Excludes blinds that just check
            let vpip = preflopPlayerActions.contains { action in
                ["CALL", "RAISE", "BET"].contains(action.actionType)
            }
            updatedPlayers[i].vpip = vpip

            // PFR: Did player raise preflop?
            let pfr = preflopPlayerActions.contains { $0.actionType == "RAISE" || $0.actionType == "BET" }
            updatedPlayers[i].pfr = pfr

            // 3-Bet: Did player make the second raise preflop?
            updatedPlayers[i].threeBet = (secondRaiseUsername == username)

            // 4-Bet: Did player make the third raise preflop?
            updatedPlayers[i].fourBet = (thirdRaiseUsername == username)

            // Cold Call: Called a raise without previously putting money in
            let coldCall = preflopPlayerActions.first(where: { $0.actionType == "CALL" }) != nil &&
                           firstRaiseUsername != nil &&
                           !preflopPlayerActions.contains(where: { $0.actionType == "RAISE" || $0.actionType == "BET" })
            updatedPlayers[i].coldCall = coldCall

            // Fold to 3-bet
            if firstRaiseUsername == username && secondRaiseUsername != nil {
                updatedPlayers[i].foldToThreeBet = preflopPlayerActions.contains { $0.actionType == "FOLD" }
            }

            // C-Bet stats
            let flopActions = actions["FLOP"] ?? []
            let turnActions = actions["TURN"] ?? []
            let riverActions = actions["RIVER"] ?? []

            // C-Bet Flop: Raised preflop and bet/raised on flop
            if firstRaiseUsername == username && !flopActions.isEmpty {
                updatedPlayers[i].cbetFlop = flopActions.contains { $0.actionType == "BET" || $0.actionType == "RAISE" }
            }

            // Fold to C-Bet Flop
            if firstRaiseUsername != username && !flopActions.isEmpty {
                let firstFlopAction = flopActions.first
                if firstFlopAction?.actionType == "BET" || firstFlopAction?.actionType == "RAISE" {
                    updatedPlayers[i].foldToCbetFlop = flopActions.contains { $0.actionType == "FOLD" }
                }
            }

            // C-Bet Turn
            if firstRaiseUsername == username && !turnActions.isEmpty {
                updatedPlayers[i].cbetTurn = turnActions.contains { $0.actionType == "BET" || $0.actionType == "RAISE" }
            }

            // Fold to C-Bet Turn
            if firstRaiseUsername != username && !turnActions.isEmpty {
                let firstTurnAction = turnActions.first
                if firstTurnAction?.actionType == "BET" || firstTurnAction?.actionType == "RAISE" {
                    updatedPlayers[i].foldToCbetTurn = turnActions.contains { $0.actionType == "FOLD" }
                }
            }

            // C-Bet River
            if firstRaiseUsername == username && !riverActions.isEmpty {
                updatedPlayers[i].cbetRiver = riverActions.contains { $0.actionType == "BET" || $0.actionType == "RAISE" }
            }

            // Fold to C-Bet River
            if firstRaiseUsername != username && !riverActions.isEmpty {
                let firstRiverAction = riverActions.first
                if firstRiverAction?.actionType == "BET" || firstRiverAction?.actionType == "RAISE" {
                    updatedPlayers[i].foldToCbetRiver = riverActions.contains { $0.actionType == "FOLD" }
                }
            }

            // Check-raise flop
            let flopCheckRaise = flopActions.count >= 2 &&
                                 flopActions[0].actionType == "CHECK" &&
                                 flopActions[1].actionType == "RAISE"
            updatedPlayers[i].checkRaiseFlop = flopCheckRaise

            // Aggression Factor: (Bets + Raises) / Calls
            let allPlayerActions = actions.values.flatMap { $0 }
            let aggressiveActions = allPlayerActions.filter { $0.actionType == "BET" || $0.actionType == "RAISE" }.count
            let passiveActions = allPlayerActions.filter { $0.actionType == "CALL" }.count

            if passiveActions > 0 {
                updatedPlayers[i].aggressionFactor = Double(aggressiveActions) / Double(passiveActions)
            } else if aggressiveActions > 0 {
                updatedPlayers[i].aggressionFactor = Double(aggressiveActions)
            }

            // All-in
            updatedPlayers[i].allIn = allPlayerActions.contains { $0.actionType == "ALL_IN" }
        }

        return updatedPlayers
    }

    /// Fetch aggregated stats for a player
    /// - Parameters:
    ///   - playerId: Player ID
    ///   - filters: Optional filters to apply
    /// - Returns: Aggregated player statistics
    func getPlayerStats(playerId: Int64, filters: StatFilters? = nil) throws -> PlayerStats? {
        try statsRepository.fetchPlayerStats(playerId: playerId, filters: filters)
    }

    /// Fetch stats for all players
    /// - Parameters:
    ///   - minHands: Minimum hands to include player
    ///   - filters: Optional filters to apply
    /// - Returns: Array of player statistics
    func getAllPlayerStats(minHands: Int = 10, filters: StatFilters? = nil) throws -> [PlayerStats] {
        try statsRepository.fetchAllPlayerStats(minHands: minHands, filters: filters)
    }
}
