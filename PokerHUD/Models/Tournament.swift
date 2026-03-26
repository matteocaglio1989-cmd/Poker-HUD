import Foundation
import GRDB

struct Tournament: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var siteId: Int64
    var tournamentId: String
    var name: String?
    var buyIn: Double?
    var rake: Double?
    var bounty: Double?
    var prizePool: Double?
    var finishPosition: Int?
    var totalPlayers: Int?
    var payout: Double?
    var startTime: Date?
    var endTime: Date?
    var gameType: String?  // HOLDEM, OMAHA, etc.

    static let databaseTableName = "tournaments"

    enum Columns: String, ColumnExpression {
        case id, siteId, tournamentId, name, buyIn, rake, bounty
        case prizePool, finishPosition, totalPlayers, payout
        case startTime, endTime, gameType
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Tournament: Identifiable {}

extension Tournament {
    static let site = belongsTo(Site.self)
    static let hands = hasMany(Hand.self)
}

enum GameType: String, CaseIterable {
    case holdem = "HOLDEM"
    case omaha = "OMAHA"
    case omaha5 = "OMAHA_5"
    case sevenCardStud = "SEVEN_CARD_STUD"
    case razz = "RAZZ"
    case horsE = "HORSE"
    case mixed = "MIXED"

    var displayName: String {
        switch self {
        case .holdem: return "No Limit Hold'em"
        case .omaha: return "Pot Limit Omaha"
        case .omaha5: return "5-Card PLO"
        case .sevenCardStud: return "7-Card Stud"
        case .razz: return "Razz"
        case .horsE: return "HORSE"
        case .mixed: return "Mixed Games"
        }
    }
}

enum LimitType: String, CaseIterable {
    case noLimit = "NL"
    case potLimit = "PL"
    case fixedLimit = "FL"

    var displayName: String {
        switch self {
        case .noLimit: return "No Limit"
        case .potLimit: return "Pot Limit"
        case .fixedLimit: return "Fixed Limit"
        }
    }
}
