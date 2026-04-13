import Foundation
import GRDB

class DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue!

    private init() {
        do {
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let dbDirectory = appSupport.appendingPathComponent("PokerHUD", isDirectory: true)
            try fileManager.createDirectory(at: dbDirectory, withIntermediateDirectories: true)

            let dbPath = dbDirectory.appendingPathComponent("poker.db").path
            var config = Configuration()
            config.prepareDatabase { db in
                // Use WAL mode for better concurrent read/write performance
                try db.execute(sql: "PRAGMA journal_mode = WAL")
                try db.execute(sql: "PRAGMA busy_timeout = 5000")
            }
            dbQueue = try DatabaseQueue(path: dbPath, configuration: config)

            try migrator.migrate(dbQueue)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    var reader: DatabaseReader {
        dbQueue
    }

    var writer: DatabaseWriter {
        dbQueue
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            // Sites table
            try db.create(table: "sites") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("handHistoryPath", .text)
                t.column("autoImport", .boolean).notNull().defaults(to: true)
            }

            // Players table
            try db.create(table: "players") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("siteId", .integer).notNull()
                    .references("sites", onDelete: .cascade)
                t.column("username", .text).notNull()
                t.column("alias", .text)
                t.column("notes", .text)
                t.column("playerType", .text)
                t.uniqueKey(["siteId", "username"])
            }

            // Tournaments table
            try db.create(table: "tournaments") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("siteId", .integer).notNull()
                    .references("sites", onDelete: .cascade)
                t.column("tournamentId", .text).notNull()
                t.column("name", .text)
                t.column("buyIn", .double)
                t.column("rake", .double)
                t.column("bounty", .double)
                t.column("prizePool", .double)
                t.column("finishPosition", .integer)
                t.column("totalPlayers", .integer)
                t.column("payout", .double)
                t.column("startTime", .datetime)
                t.column("endTime", .datetime)
                t.column("gameType", .text)
                t.uniqueKey(["siteId", "tournamentId"])
            }

            // Hands table
            try db.create(table: "hands") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("siteId", .integer).notNull()
                    .references("sites", onDelete: .cascade)
                t.column("handId", .text).notNull()
                t.column("tournamentId", .integer)
                    .references("tournaments", onDelete: .setNull)
                t.column("tableName", .text)
                t.column("gameType", .text).notNull()
                t.column("limitType", .text).notNull()
                t.column("tableSize", .integer)
                t.column("smallBlind", .double).notNull()
                t.column("bigBlind", .double).notNull()
                t.column("ante", .double).notNull().defaults(to: 0)
                t.column("board", .text)
                t.column("potTotal", .double).notNull()
                t.column("rake", .double).notNull()
                t.column("playedAt", .datetime).notNull()
                t.column("rawText", .text)
                t.uniqueKey(["siteId", "handId"])
            }

            // Hand players table
            try db.create(table: "hand_players") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("handId", .integer).notNull()
                    .references("hands", onDelete: .cascade)
                t.column("playerId", .integer).notNull()
                    .references("players", onDelete: .cascade)
                t.column("seat", .integer).notNull()
                t.column("position", .text)
                t.column("holeCards", .text)
                t.column("isHero", .boolean).notNull().defaults(to: false)
                t.column("startingStack", .double).notNull()
                t.column("totalBet", .double).notNull()
                t.column("totalWon", .double).notNull()
                t.column("netResult", .double).notNull()
                t.column("wentToShowdown", .boolean).notNull().defaults(to: false)
                t.column("wonAtShowdown", .boolean).notNull().defaults(to: false)

                // Preflop
                t.column("vpip", .boolean).notNull().defaults(to: false)
                t.column("pfr", .boolean).notNull().defaults(to: false)
                t.column("threeBet", .boolean).notNull().defaults(to: false)
                t.column("fourBet", .boolean).notNull().defaults(to: false)
                t.column("coldCall", .boolean).notNull().defaults(to: false)
                t.column("squeeze", .boolean).notNull().defaults(to: false)
                t.column("foldToThreeBet", .boolean)

                // Flop
                t.column("cbetFlop", .boolean)
                t.column("foldToCbetFlop", .boolean)
                t.column("checkRaiseFlop", .boolean)

                // Turn
                t.column("cbetTurn", .boolean)
                t.column("foldToCbetTurn", .boolean)

                // River
                t.column("cbetRiver", .boolean)
                t.column("foldToCbetRiver", .boolean)

                // General
                t.column("aggressionFactor", .double)
                t.column("allIn", .boolean).notNull().defaults(to: false)

                t.uniqueKey(["handId", "playerId"])
            }

            // Actions table
            try db.create(table: "actions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("handId", .integer).notNull()
                    .references("hands", onDelete: .cascade)
                t.column("playerId", .integer).notNull()
                    .references("players", onDelete: .cascade)
                t.column("street", .text).notNull()
                t.column("actionOrder", .integer).notNull()
                t.column("actionType", .text).notNull()
                t.column("amount", .double).notNull().defaults(to: 0)
                t.column("potBefore", .double)
                t.column("potAfter", .double)
            }

            // Player notes table
            try db.create(table: "player_notes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("playerId", .integer).notNull()
                    .references("players", onDelete: .cascade)
                t.column("note", .text)
                t.column("color", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Hand tags table
            try db.create(table: "hand_tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("handId", .integer).notNull()
                    .references("hands", onDelete: .cascade)
                t.column("tag", .text).notNull()
                t.column("note", .text)
                t.column("createdAt", .datetime).notNull()
            }

            // Sessions table
            try db.create(table: "sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("siteId", .integer).notNull()
                    .references("sites", onDelete: .cascade)
                t.column("tableName", .text)
                t.column("gameType", .text)
                t.column("stakes", .text)
                t.column("startTime", .datetime).notNull()
                t.column("endTime", .datetime)
                t.column("handsPlayed", .integer).notNull().defaults(to: 0)
                t.column("netResult", .double).notNull().defaults(to: 0)
                t.column("isTournament", .boolean).notNull().defaults(to: false)
                t.column("tournamentId", .integer)
                    .references("tournaments", onDelete: .setNull)
            }

            // Create indexes
            try db.create(index: "idx_hands_played_at", on: "hands", columns: ["playedAt"])
            try db.create(index: "idx_hands_site", on: "hands", columns: ["siteId"])
            try db.create(index: "idx_hand_players_player", on: "hand_players", columns: ["playerId"])
            try db.create(index: "idx_hand_players_hand", on: "hand_players", columns: ["handId"])
            try db.create(index: "idx_actions_hand", on: "actions", columns: ["handId"])
            try db.create(index: "idx_actions_player", on: "actions", columns: ["playerId"])
            try db.create(index: "idx_sessions_site", on: "sessions", columns: ["siteId"])
        }

        return migrator
    }
}
