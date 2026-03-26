import Foundation
import GRDB

struct PlayerNote: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var playerId: Int64
    var note: String?
    var color: String?
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "player_notes"

    enum Columns: String, ColumnExpression {
        case id, playerId, note, color, createdAt, updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension PlayerNote: Identifiable {}

extension PlayerNote {
    static let player = belongsTo(Player.self)
}
