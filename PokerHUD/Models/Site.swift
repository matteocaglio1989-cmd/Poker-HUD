import Foundation
import GRDB

struct Site: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var name: String
    var handHistoryPath: String?
    var autoImport: Bool

    static let databaseTableName = "sites"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Site: Identifiable {}

extension Site {
    enum Columns: String, ColumnExpression {
        case id, name, handHistoryPath, autoImport
    }
}

extension Site {
    static let players = hasMany(Player.self)
    static let hands = hasMany(Hand.self)
    static let tournaments = hasMany(Tournament.self)
}
