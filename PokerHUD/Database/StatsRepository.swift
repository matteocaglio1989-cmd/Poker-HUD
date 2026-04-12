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
                if let moneyType = filters.moneyType {
                    sql += " AND h.moneyType = ?"
                    arguments.append(moneyType)
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
                if let moneyType = filters.moneyType {
                    sql += " AND h.moneyType = ?"
                    arguments.append(moneyType)
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

    // MARK: - Hole Card Matrix (Phase 3 PR4)

    /// Fetch the 169-cell hole-card matrix for a single player. Used by
    /// `HoleCardHeatMapView`.
    ///
    /// SQL groups by the literal `holeCards` string (e.g. `"Ah Kd"`) and
    /// the Swift mapper folds those into the canonical 169 buckets via
    /// `HoleCardClassifier.bucket(for:)`. We do the bucket folding in
    /// Swift instead of SQL because (a) the cardinality is bounded
    /// (≤1326 distinct rank+suit pairs at the absolute worst, usually
    /// far fewer in practice) and (b) the bucket logic is non-trivial
    /// SQL but trivial Swift.
    ///
    /// Returns an "empty matrix" with all 169 cells at zero samples
    /// when the player has no hole-card data — that lets the view
    /// render a uniform grid regardless of sample size.
    func fetchHoleCardMatrix(playerName: String, filters: StatFilters? = nil) throws -> HoleCardMatrix {
        guard !playerName.isEmpty else {
            return HoleCardMatrix.empty(playerName: playerName)
        }
        return try dbManager.reader.read { db in
            var sql = """
                SELECT
                    hp.holeCards AS holeCards,
                    COUNT(*) AS handsDealt,
                    SUM(CASE WHEN hp.wonAtShowdown = 1 THEN 1 ELSE 0 END) AS handsWon,
                    SUM(hp.netResult) AS totalNet
                FROM hand_players hp
                INNER JOIN players p ON p.id = hp.playerId
                INNER JOIN hands h ON h.id = hp.handId
                WHERE p.username = ?
                  AND hp.holeCards IS NOT NULL
                  AND hp.holeCards != ''
                """
            var arguments: [DatabaseValueConvertible] = [playerName]

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
                if let moneyType = filters.moneyType {
                    sql += " AND h.moneyType = ?"
                    arguments.append(moneyType)
                }
                if let minStakes = filters.minStakes {
                    sql += " AND h.bigBlind >= ?"
                    arguments.append(minStakes)
                }
                if let maxStakes = filters.maxStakes {
                    sql += " AND h.bigBlind <= ?"
                    arguments.append(maxStakes)
                }
            }

            sql += " GROUP BY hp.holeCards"

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

            // Aggregate raw rows into the 169 canonical buckets.
            var aggregates: [HoleCardBucket: (dealt: Int, won: Int, net: Double)] = [:]
            var totalHands = 0
            for row in rows {
                let holeCards: String = row["holeCards"] ?? ""
                let handsDealt: Int = row["handsDealt"] ?? 0
                let handsWon: Int = row["handsWon"] ?? 0
                let totalNet: Double = row["totalNet"] ?? 0
                totalHands += handsDealt
                guard let bucket = HoleCardClassifier.bucket(for: holeCards) else { continue }
                let prev = aggregates[bucket] ?? (0, 0, 0.0)
                aggregates[bucket] = (
                    prev.dealt + handsDealt,
                    prev.won + handsWon,
                    prev.net + totalNet
                )
            }

            // Lay out into a 13×13 grid, filling missing buckets with
            // zero samples so the view always renders a complete chart.
            var grid: [[HoleCardCellStats]] = Array(
                repeating: Array(
                    repeating: HoleCardCellStats(
                        bucket: HoleCardBucket(highRankIndex: 0, lowRankIndex: 0, isSuited: false),
                        handsDealt: 0, handsWon: 0, totalNet: 0
                    ),
                    count: 13
                ),
                count: 13
            )
            for bucket in HoleCardClassifier.allBuckets() {
                let pos = bucket.gridPosition
                let agg = aggregates[bucket] ?? (0, 0, 0.0)
                grid[pos.row][pos.col] = HoleCardCellStats(
                    bucket: bucket,
                    handsDealt: agg.dealt,
                    handsWon: agg.won,
                    totalNet: agg.net
                )
            }

            return HoleCardMatrix(
                playerName: playerName,
                totalHands: totalHands,
                cellsByPosition: grid
            )
        }
    }

    // MARK: - Situational Stats (Phase 3 PR2)

    /// Fetch situational breakdown for a single player, split by pre-flop
    /// pot type (single-raised vs 3-bet+). Runtime computation — no
    /// schema changes required: a CTE counts `actions` rows with
    /// `street='PREFLOP'` and `actionType IN ('RAISE','BET')` per hand,
    /// then the main query conditionally sums the already-stored
    /// `cbetFlop` / `foldToCbetFlop` / etc. booleans by the CTE's raise
    /// count.
    ///
    /// "Single-raised pot" = exactly 1 preflop raise. "3-bet+ pot" = 2 or
    /// more. Turn and river c-bet stats are not split by pot type because
    /// the sample sizes get too small to be interesting at the
    /// per-session level.
    ///
    /// Returns nil when the player has no hands matching the filter.
    func fetchSituationalStats(playerName: String, filters: StatFilters? = nil) throws -> SituationalStats? {
        guard !playerName.isEmpty else { return nil }
        return try dbManager.reader.read { db in
            var sql = """
                WITH hand_preflop_raises AS (
                    SELECT handId, COUNT(*) AS raiseCount
                    FROM actions
                    WHERE street = 'PREFLOP' AND actionType IN ('RAISE', 'BET')
                    GROUP BY handId
                )
                SELECT
                    p.id AS playerId,
                    p.username AS playerName,
                    COUNT(DISTINCT hp.handId) AS handsPlayed,
                    -- C-bet flop split by pot type
                    SUM(CASE WHEN COALESCE(hpr.raiseCount, 0) = 1 AND hp.cbetFlop = 1 THEN 1 ELSE 0 END) AS cbetFlopSRPHits,
                    SUM(CASE WHEN COALESCE(hpr.raiseCount, 0) = 1 AND hp.cbetFlop IS NOT NULL THEN 1 ELSE 0 END) AS cbetFlopSRPOpps,
                    SUM(CASE WHEN COALESCE(hpr.raiseCount, 0) >= 2 AND hp.cbetFlop = 1 THEN 1 ELSE 0 END) AS cbetFlop3BPHits,
                    SUM(CASE WHEN COALESCE(hpr.raiseCount, 0) >= 2 AND hp.cbetFlop IS NOT NULL THEN 1 ELSE 0 END) AS cbetFlop3BPOpps,
                    -- Fold to c-bet flop split by pot type
                    SUM(CASE WHEN COALESCE(hpr.raiseCount, 0) = 1 AND hp.foldToCbetFlop = 1 THEN 1 ELSE 0 END) AS foldCbetFlopSRPHits,
                    SUM(CASE WHEN COALESCE(hpr.raiseCount, 0) = 1 AND hp.foldToCbetFlop IS NOT NULL THEN 1 ELSE 0 END) AS foldCbetFlopSRPOpps,
                    SUM(CASE WHEN COALESCE(hpr.raiseCount, 0) >= 2 AND hp.foldToCbetFlop = 1 THEN 1 ELSE 0 END) AS foldCbetFlop3BPHits,
                    SUM(CASE WHEN COALESCE(hpr.raiseCount, 0) >= 2 AND hp.foldToCbetFlop IS NOT NULL THEN 1 ELSE 0 END) AS foldCbetFlop3BPOpps,
                    -- Turn / River (not split)
                    SUM(CASE WHEN hp.cbetTurn = 1 THEN 1 ELSE 0 END) AS cbetTurnHits,
                    SUM(CASE WHEN hp.cbetTurn IS NOT NULL THEN 1 ELSE 0 END) AS cbetTurnOpps,
                    SUM(CASE WHEN hp.cbetRiver = 1 THEN 1 ELSE 0 END) AS cbetRiverHits,
                    SUM(CASE WHEN hp.cbetRiver IS NOT NULL THEN 1 ELSE 0 END) AS cbetRiverOpps,
                    SUM(CASE WHEN hp.foldToCbetTurn = 1 THEN 1 ELSE 0 END) AS foldCbetTurnHits,
                    SUM(CASE WHEN hp.foldToCbetTurn IS NOT NULL THEN 1 ELSE 0 END) AS foldCbetTurnOpps,
                    SUM(CASE WHEN hp.foldToCbetRiver = 1 THEN 1 ELSE 0 END) AS foldCbetRiverHits,
                    SUM(CASE WHEN hp.foldToCbetRiver IS NOT NULL THEN 1 ELSE 0 END) AS foldCbetRiverOpps
                FROM players p
                INNER JOIN hand_players hp ON hp.playerId = p.id
                INNER JOIN hands h ON h.id = hp.handId
                LEFT JOIN hand_preflop_raises hpr ON hpr.handId = hp.handId
                WHERE p.username = ?
                """
            var arguments: [DatabaseValueConvertible] = [playerName]

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
                if let moneyType = filters.moneyType {
                    sql += " AND h.moneyType = ?"
                    arguments.append(moneyType)
                }
                if let minStakes = filters.minStakes {
                    sql += " AND h.bigBlind >= ?"
                    arguments.append(minStakes)
                }
                if let maxStakes = filters.maxStakes {
                    sql += " AND h.bigBlind <= ?"
                    arguments.append(maxStakes)
                }
            }

            sql += " GROUP BY p.id, p.username"

            guard let row = try Row.fetchOne(db, sql: sql, arguments: StatementArguments(arguments)) else {
                return nil
            }
            let handsPlayed: Int = row["handsPlayed"] ?? 0
            guard handsPlayed > 0 else { return nil }

            return SituationalStats(
                playerId: row["playerId"] ?? 0,
                playerName: row["playerName"] ?? playerName,
                handsPlayed: handsPlayed,
                cbetFlopSRPHits: row["cbetFlopSRPHits"] ?? 0,
                cbetFlopSRPOpps: row["cbetFlopSRPOpps"] ?? 0,
                cbetFlop3BPHits: row["cbetFlop3BPHits"] ?? 0,
                cbetFlop3BPOpps: row["cbetFlop3BPOpps"] ?? 0,
                foldCbetFlopSRPHits: row["foldCbetFlopSRPHits"] ?? 0,
                foldCbetFlopSRPOpps: row["foldCbetFlopSRPOpps"] ?? 0,
                foldCbetFlop3BPHits: row["foldCbetFlop3BPHits"] ?? 0,
                foldCbetFlop3BPOpps: row["foldCbetFlop3BPOpps"] ?? 0,
                cbetTurnHits: row["cbetTurnHits"] ?? 0,
                cbetTurnOpps: row["cbetTurnOpps"] ?? 0,
                cbetRiverHits: row["cbetRiverHits"] ?? 0,
                cbetRiverOpps: row["cbetRiverOpps"] ?? 0,
                foldCbetTurnHits: row["foldCbetTurnHits"] ?? 0,
                foldCbetTurnOpps: row["foldCbetTurnOpps"] ?? 0,
                foldCbetRiverHits: row["foldCbetRiverHits"] ?? 0,
                foldCbetRiverOpps: row["foldCbetRiverOpps"] ?? 0
            )
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
    /// `"CASH"`, `"TOURNAMENT"`, or `"PLAY_MONEY"`. Nil = all.
    var moneyType: String?
}

/// Filter enum for the money-type picker used across Reports,
/// Sessions, and Hand Replayer. Shared here so all three views
/// import a single source of truth.
enum MoneyTypeFilter: String, CaseIterable, Identifiable {
    case all       = "All"
    case cash      = "Cash"
    case tournament = "Tournament"
    case playMoney = "Play Money"

    var id: String { rawValue }

    /// The raw DB value to filter on, or nil for "all".
    var dbValue: String? {
        switch self {
        case .all:        return nil
        case .cash:       return "CASH"
        case .tournament: return "TOURNAMENT"
        case .playMoney:  return "PLAY_MONEY"
        }
    }
}
