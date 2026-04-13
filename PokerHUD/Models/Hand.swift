import Foundation
import GRDB

struct Hand: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var siteId: Int64
    var handId: String
    var tournamentId: Int64?
    var tableName: String?
    var gameType: String
    var limitType: String
    var tableSize: Int?
    var smallBlind: Double
    var bigBlind: Double
    var ante: Double
    var board: String?  // e.g. "Ah Kd 7s 2c Jh"
    var potTotal: Double
    var rake: Double
    var playedAt: Date
    var rawText: String?

    static let databaseTableName = "hands"

    enum Columns: String, ColumnExpression {
        case id, siteId, handId, tournamentId, tableName
        case gameType, limitType, tableSize, smallBlind, bigBlind
        case ante, board, potTotal, rake, playedAt, rawText
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Hand: Identifiable {}

extension Hand {
    static let site = belongsTo(Site.self)
    static let tournament = belongsTo(Tournament.self)
    static let handPlayers = hasMany(HandPlayer.self)
    static let actions = hasMany(Action.self)
    static let tags = hasMany(HandTag.self)

    var stakes: String {
        if ante > 0 {
            return "\(smallBlind)/\(bigBlind)/\(ante)"
        }
        return "\(smallBlind)/\(bigBlind)"
    }

    var boardCards: [String] {
        guard let board = board else { return [] }
        return board.split(separator: " ").map(String.init)
    }

    var isTournament: Bool {
        tournamentId != nil
    }
}
