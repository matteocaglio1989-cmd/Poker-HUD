import Foundation
import GRDB

class StatsRepository {
    private let dbManager: DatabaseManager

    init(databaseManager: DatabaseManager = .shared) {
        self.dbManager = databaseManager
    }

    // MARK: - Player Stats

    func fetchPlayerStats(playerId: Int64, filters: StatFilters? = nil) throws -> PlayerStats? {
        try dbManager.reader.read { db in
            var sql = """
                SELECT
                    p.id as playerId,
                    p.username as playerName,
                    COUNT(DISTINCT hp.handId) as handsPlayed,
                    ROUND(AVG(CASE WHEN hp.vpip = 1 THEN 100.0 ELSE 0.0 END), 2) as vpip,
                    ROUND(AVG(CASE WHEN hp.pfr = 1 THEN 100.0 ELSE 0.0 END), 2) as pfr,
                    ROUND(AVG(CASE WHEN hp.threeBet = 1 THEN 100.0 ELSE 0.0 END), 2) as threeBet,
                    ROUND(AVG(CASE WHEN hp.fourBet = 1 THEN 100.0 ELSE 0.0 END), 2) as fourBet,
                    ROUND(AVG(CASE WHEN hp.foldToThreeBet = 1 THEN 100.0 ELSE 0.0 END), 2) as foldToThreeBet,
                    ROUND(AVG(CASE WHEN hp.coldCall = 1 THEN 100.0 ELSE 0.0 END), 2) as coldCall,
                    ROUND(AVG(CASE WHEN hp.squeeze = 1 THEN 100.0 ELSE 0.0 END), 2) as squeeze,
                    ROUND(AVG(COALESCE(hp.aggressionFactor, 0)), 2) as aggressionFactor,
                    ROUND(AVG(CASE WHEN hp.cbetFlop = 1 THEN 100.0 ELSE 0.0 END), 2) as cbetFlop,
                    ROUND(AVG(CASE WHEN hp.cbetTurn = 1 THEN 100.0 ELSE 0.0 END), 2) as cbetTurn,
                    ROUND(AVG(CASE WHEN hp.cbetRiver = 1 THEN 100.0 ELSE 0.0 END), 2) as cbetRiver,
                    ROUND(AVG(CASE WHEN hp.foldToCbetFlop = 1 THEN 100.0 ELSE 0.0 END), 2) as foldToCbetFlop,
                    ROUND(AVG(CASE WHEN hp.foldToCbetTurn = 1 THEN 100.0 ELSE 0.0 END), 2) as foldToCbetTurn,
                    ROUND(AVG(CASE WHEN hp.foldToCbetRiver = 1 THEN 100.0 ELSE 0.0 END), 2) as foldToCbetRiver,
                    ROUND(AVG(CASE WHEN hp.wentToShowdown = 1 THEN 100.0 ELSE 0.0 END), 2) as wtsd,
                    ROUND(AVG(CASE WHEN hp.wonAtShowdown = 1 AND hp.wentToShowdown = 1 THEN 100.0 ELSE 0.0 END), 2) as wsd,
                    SUM(hp.netResult) as totalWon,
                    ROUND((SUM(hp.netResult) / AVG(h.bigBlind)) / COUNT(DISTINCT hp.handId) * 100, 2) as bb100
                FROM players p
                INNER JOIN hand_players hp ON hp.playerId = p.id
                INNER JOIN hands h ON h.id = hp.handId
                WHERE p.id = ?
                """

            var arguments: [DatabaseValueConvertible] = [playerId]

            if let filters = filters {
                if let fromDate = filters.fromDate {
                    sql += " AND h.playedAt >= ?"
                    arguments.append(fromDate)
                }
                if let toDate = filters.toDate {
                    sql += " AND h.playedAt <= ?"
                    arguments.append(toDate)
                }
                if let position = filters.position {
                    sql += " AND hp.position = ?"
                    arguments.append(position)
                }
                if let gameType = filters.gameType {
                    sql += " AND h.gameType = ?"
                    arguments.append(gameType)
                }
            }

            guard let row = try Row.fetchOne(db, sql: sql, arguments: StatementArguments(arguments)) else {
                return nil
            }

            let handsPlayed: Int = row["handsPlayed"]
            guard handsPlayed > 0 else { return nil }

            return PlayerStats(
                playerId: row["playerId"] ?? playerId,
                playerName: row["playerName"] ?? "",
                handsPlayed: handsPlayed,
                vpip: row["vpip"] ?? 0.0,
                pfr: row["pfr"] ?? 0.0,
                threeBet: row["threeBet"] ?? 0.0,
                fourBet: row["fourBet"] ?? 0.0,
                foldToThreeBet: row["foldToThreeBet"] ?? 0.0,
                coldCall: row["coldCall"] ?? 0.0,
                squeeze: row["squeeze"] ?? 0.0,
                aggressionFactor: row["aggressionFactor"] ?? 0.0,
                aggressionPercentage: 0.0,  // Calculate separately if needed
                cbetFlop: row["cbetFlop"] ?? 0.0,
                cbetTurn: row["cbetTurn"] ?? 0.0,
                cbetRiver: row["cbetRiver"] ?? 0.0,
                foldToCbetFlop: row["foldToCbetFlop"] ?? 0.0,
                foldToCbetTurn: row["foldToCbetTurn"] ?? 0.0,
                foldToCbetRiver: row["foldToCbetRiver"] ?? 0.0,
                wtsd: row["wtsd"] ?? 0.0,
                wsd: row["wsd"] ?? 0.0,
                totalWon: row["totalWon"] ?? 0.0,
                bb100: row["bb100"] ?? 0.0
            )
        }
    }

    func fetchAllPlayerStats(minHands: Int = 10, filters: StatFilters? = nil) throws -> [PlayerStats] {
        try dbManager.reader.read { db in
            var sql = """
                SELECT
                    p.id as playerId,
                    p.username as playerName,
                    COUNT(DISTINCT hp.handId) as handsPlayed,
                    ROUND(AVG(CASE WHEN hp.vpip = 1 THEN 100.0 ELSE 0.0 END), 2) as vpip,
                    ROUND(AVG(CASE WHEN hp.pfr = 1 THEN 100.0 ELSE 0.0 END), 2) as pfr,
                    ROUND(AVG(CASE WHEN hp.threeBet = 1 THEN 100.0 ELSE 0.0 END), 2) as threeBet,
                    ROUND(AVG(CASE WHEN hp.fourBet = 1 THEN 100.0 ELSE 0.0 END), 2) as fourBet,
                    ROUND(AVG(CASE WHEN hp.foldToThreeBet = 1 THEN 100.0 ELSE 0.0 END), 2) as foldToThreeBet,
                    ROUND(AVG(CASE WHEN hp.coldCall = 1 THEN 100.0 ELSE 0.0 END), 2) as coldCall,
                    ROUND(AVG(CASE WHEN hp.squeeze = 1 THEN 100.0 ELSE 0.0 END), 2) as squeeze,
                    ROUND(AVG(COALESCE(hp.aggressionFactor, 0)), 2) as aggressionFactor,
                    ROUND(AVG(CASE WHEN hp.cbetFlop = 1 THEN 100.0 ELSE 0.0 END), 2) as cbetFlop,
                    ROUND(AVG(CASE WHEN hp.cbetTurn = 1 THEN 100.0 ELSE 0.0 END), 2) as cbetTurn,
                    ROUND(AVG(CASE WHEN hp.cbetRiver = 1 THEN 100.0 ELSE 0.0 END), 2) as cbetRiver,
                    ROUND(AVG(CASE WHEN hp.foldToCbetFlop = 1 THEN 100.0 ELSE 0.0 END), 2) as foldToCbetFlop,
                    ROUND(AVG(CASE WHEN hp.foldToCbetTurn = 1 THEN 100.0 ELSE 0.0 END), 2) as foldToCbetTurn,
                    ROUND(AVG(CASE WHEN hp.foldToCbetRiver = 1 THEN 100.0 ELSE 0.0 END), 2) as foldToCbetRiver,
                    ROUND(AVG(CASE WHEN hp.wentToShowdown = 1 THEN 100.0 ELSE 0.0 END), 2) as wtsd,
                    ROUND(AVG(CASE WHEN hp.wonAtShowdown = 1 AND hp.wentToShowdown = 1 THEN 100.0 ELSE 0.0 END), 2) as wsd,
                    SUM(hp.netResult) as totalWon,
                    ROUND((SUM(hp.netResult) / AVG(h.bigBlind)) / COUNT(DISTINCT hp.handId) * 100, 2) as bb100
                FROM players p
                INNER JOIN hand_players hp ON hp.playerId = p.id
                INNER JOIN hands h ON h.id = hp.handId
                WHERE 1=1
                """

            var arguments: [DatabaseValueConvertible] = []

            if let filters = filters {
                if let fromDate = filters.fromDate {
                    sql += " AND h.playedAt >= ?"
                    arguments.append(fromDate)
                }
                if let toDate = filters.toDate {
                    sql += " AND h.playedAt <= ?"
                    arguments.append(toDate)
                }
                if let position = filters.position {
                    sql += " AND hp.position = ?"
                    arguments.append(position)
                }
                if let gameType = filters.gameType {
                    sql += " AND h.gameType = ?"
                    arguments.append(gameType)
                }
                if let minStakes = filters.minStakes {
                    sql += " AND h.bigBlind >= ?"
                    arguments.append(minStakes)
                }
                if let maxStakes = filters.maxStakes {
                    sql += " AND h.bigBlind <= ?"
                    arguments.append(maxStakes)
                }
                if let heroName = filters.heroPlayerName, !heroName.isEmpty {
                    // Restrict to hands in which the hero participated.
                    // Subquery: hand IDs where some hand_player has isHero=1
                    // and the player's username matches. This both keeps
                    // the hero himself in the result (he'll match his own
                    // hand IDs) and limits opponents to those who actually
                    // sat with him.
                    sql += """
                         AND hp.handId IN (
                             SELECT hp2.handId FROM hand_players hp2
                             INNER JOIN players p2 ON p2.id = hp2.playerId
                             WHERE hp2.isHero = 1 AND p2.username = ?
                         )
                        """
                    arguments.append(heroName)
                }
            }

            sql += " GROUP BY p.id, p.username HAVING COUNT(DISTINCT hp.handId) >= ? ORDER BY handsPlayed DESC"
            arguments.append(minHands)

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

            return rows.map { row in
                PlayerStats(
                    playerId: row["playerId"] ?? 0,
                    playerName: row["playerName"] ?? "",
                    handsPlayed: row["handsPlayed"] ?? 0,
                    vpip: row["vpip"] ?? 0.0,
                    pfr: row["pfr"] ?? 0.0,
                    threeBet: row["threeBet"] ?? 0.0,
                    fourBet: row["fourBet"] ?? 0.0,
                    foldToThreeBet: row["foldToThreeBet"] ?? 0.0,
                    coldCall: row["coldCall"] ?? 0.0,
                    squeeze: row["squeeze"] ?? 0.0,
                    aggressionFactor: row["aggressionFactor"] ?? 0.0,
                    aggressionPercentage: 0.0,
                    cbetFlop: row["cbetFlop"] ?? 0.0,
                    cbetTurn: row["cbetTurn"] ?? 0.0,
                    cbetRiver: row["cbetRiver"] ?? 0.0,
                    foldToCbetFlop: row["foldToCbetFlop"] ?? 0.0,
                    foldToCbetTurn: row["foldToCbetTurn"] ?? 0.0,
                    foldToCbetRiver: row["foldToCbetRiver"] ?? 0.0,
                    wtsd: row["wtsd"] ?? 0.0,
                    wsd: row["wsd"] ?? 0.0,
                    totalWon: row["totalWon"] ?? 0.0,
                    bb100: row["bb100"] ?? 0.0
                )
            }
        }
    }
}

// MARK: - Stat Filters

/// Filter set for player stats queries.
///
/// Phase 3 PR1 wires the previously dormant `position`/`gameType` SQL paths
/// to the UI and adds `minStakes`/`maxStakes` (filtering on `h.bigBlind`)
/// plus `heroPlayerName` — when set, the bulk player-stats query restricts
/// the result to **opponents who played in at least one hand with this
/// hero**, plus the hero himself. The same join-style restriction is what
/// the user expected when they first added the hero picker but the SQL
/// never honoured it.
struct StatFilters {
    var fromDate: Date?
    var toDate: Date?
    var position: String?
    var gameType: String?
    var minStakes: Double?   // big blind lower bound, inclusive
    var maxStakes: Double?   // big blind upper bound, inclusive
    var siteId: Int64?
    /// When non-nil, fetchAllPlayerStats filters its result to players who
    /// shared at least one hand with this hero. Single-player fetches
    /// (`fetchPlayerStats(playerId:filters:)`) ignore this field.
    var heroPlayerName: String?
}
