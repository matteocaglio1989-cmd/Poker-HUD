import Foundation
import GRDB

class PlayerRepository {
    private let dbManager: DatabaseManager

    init(databaseManager: DatabaseManager = .shared) {
        self.dbManager = databaseManager
    }

    // MARK: - Create

    func insert(_ player: inout Player) throws {
        try dbManager.writer.write { db in
            try player.insert(db)
        }
    }

    func findOrCreate(username: String, siteId: Int64) throws -> Player {
        try dbManager.writer.write { db in
            if let existing = try Player
                .filter(Player.Columns.username == username && Player.Columns.siteId == siteId)
                .fetchOne(db) {
                return existing
            }

            var newPlayer = Player(
                id: nil,
                siteId: siteId,
                username: username,
                alias: nil,
                notes: nil,
                playerType: nil
            )
            try newPlayer.insert(db)
            return newPlayer
        }
    }

    // MARK: - Read

    func fetchAll() throws -> [Player] {
        try dbManager.reader.read { db in
            try Player.fetchAll(db)
        }
    }

    func fetchById(_ id: Int64) throws -> Player? {
        try dbManager.reader.read { db in
            try Player.fetchOne(db, key: id)
        }
    }

    func fetchByUsername(_ username: String, siteId: Int64) throws -> Player? {
        try dbManager.reader.read { db in
            try Player
                .filter(Player.Columns.username == username && Player.Columns.siteId == siteId)
                .fetchOne(db)
        }
    }

    func fetchBySite(_ siteId: Int64) throws -> [Player] {
        try dbManager.reader.read { db in
            try Player
                .filter(Player.Columns.siteId == siteId)
                .order(Player.Columns.username)
                .fetchAll(db)
        }
    }

    func searchByUsername(_ query: String) throws -> [Player] {
        try dbManager.reader.read { db in
            try Player
                .filter(Player.Columns.username.like("%\(query)%"))
                .order(Player.Columns.username)
                .fetchAll(db)
        }
    }

    // MARK: - Update

    func update(_ player: Player) throws {
        try dbManager.writer.write { db in
            try player.update(db)
        }
    }

    func updatePlayerType(_ playerId: Int64, playerType: String) throws {
        try dbManager.writer.write { db in
            try db.execute(
                sql: "UPDATE players SET playerType = ? WHERE id = ?",
                arguments: [playerType, playerId]
            )
        }
    }

    func updateNotes(_ playerId: Int64, notes: String) throws {
        try dbManager.writer.write { db in
            try db.execute(
                sql: "UPDATE players SET notes = ? WHERE id = ?",
                arguments: [notes, playerId]
            )
        }
    }

    // MARK: - Delete

    func delete(_ player: Player) throws {
        try dbManager.writer.write { db in
            try player.delete(db)
        }
    }

    // MARK: - Notes

    func addNote(_ note: inout PlayerNote) throws {
        try dbManager.writer.write { db in
            try note.insert(db)
        }
    }

    func fetchNotes(forPlayerId playerId: Int64) throws -> [PlayerNote] {
        try dbManager.reader.read { db in
            try PlayerNote
                .filter(PlayerNote.Columns.playerId == playerId)
                .order(PlayerNote.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Statistics

    func count() throws -> Int {
        try dbManager.reader.read { db in
            try Player.fetchCount(db)
        }
    }
}
