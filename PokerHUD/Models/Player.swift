import Foundation
import GRDB

struct Player: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var siteId: Int64
    var username: String
    var alias: String?
    var notes: String?
    var playerType: String?  // LAG, TAG, NIT, FISH, etc.

    static let databaseTableName = "players"

    enum Columns: String, ColumnExpression {
        case id, siteId, username, alias, notes, playerType
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Player: Identifiable {}

extension Player {
    static let site = belongsTo(Site.self)
    static let handPlayers = hasMany(HandPlayer.self)
    static let playerNotes = hasMany(PlayerNote.self)
}

// Player types
enum PlayerType: String, CaseIterable {
    case lag = "LAG"     // Loose Aggressive
    case tag = "TAG"     // Tight Aggressive
    case nit = "NIT"     // Very tight/passive
    case fish = "FISH"   // Recreational player
    case rock = "ROCK"   // Extremely tight
    case maniac = "MANIAC" // Very loose/aggressive
    case unknown = "UNKNOWN"

    var description: String {
        switch self {
        case .lag: return "Loose Aggressive"
        case .tag: return "Tight Aggressive"
        case .nit: return "Nit"
        case .fish: return "Fish"
        case .rock: return "Rock"
        case .maniac: return "Maniac"
        case .unknown: return "Unknown"
        }
    }
}
