import Foundation
import GRDB

struct HandPlayer: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var handId: Int64
    var playerId: Int64
    var seat: Int
    var position: String?  // UTG, MP, CO, BTN, SB, BB
    var holeCards: String?
    var isHero: Bool
    var startingStack: Double
    var totalBet: Double
    var totalWon: Double
    var netResult: Double
    var wentToShowdown: Bool
    var wonAtShowdown: Bool

    // Preflop stats
    var vpip: Bool  // Voluntarily put money in pot
    var pfr: Bool   // Preflop raise
    var threeBet: Bool
    var fourBet: Bool
    var coldCall: Bool
    var squeeze: Bool
    var foldToThreeBet: Bool?

    // Flop stats
    var cbetFlop: Bool?
    var foldToCbetFlop: Bool?
    var checkRaiseFlop: Bool?

    // Turn stats
    var cbetTurn: Bool?
    var foldToCbetTurn: Bool?

    // River stats
    var cbetRiver: Bool?
    var foldToCbetRiver: Bool?

    // General stats
    var aggressionFactor: Double?
    var allIn: Bool

    static let databaseTableName = "hand_players"

    enum Columns: String, ColumnExpression {
        case id, handId, playerId, seat, position, holeCards
        case isHero, startingStack, totalBet, totalWon, netResult
        case wentToShowdown, wonAtShowdown
        case vpip, pfr, threeBet, fourBet, coldCall, squeeze, foldToThreeBet
        case cbetFlop, foldToCbetFlop, checkRaiseFlop
        case cbetTurn, foldToCbetTurn
        case cbetRiver, foldToCbetRiver
        case aggressionFactor, allIn
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension HandPlayer: Identifiable {}

extension HandPlayer {
    static let hand = belongsTo(Hand.self)
    static let player = belongsTo(Player.self)

    var cards: [String] {
        guard let holeCards = holeCards else { return [] }
        return holeCards.split(separator: " ").map(String.init)
    }
}

enum Position: String, CaseIterable {
    case utg = "UTG"
    case utgPlus1 = "UTG+1"
    case utgPlus2 = "UTG+2"
    case mp = "MP"
    case lojack = "LJ"
    case hijack = "HJ"
    case cutoff = "CO"
    case button = "BTN"
    case smallBlind = "SB"
    case bigBlind = "BB"

    var isEarlyPosition: Bool {
        [.utg, .utgPlus1, .utgPlus2].contains(self)
    }

    var isMiddlePosition: Bool {
        [.mp, .lojack].contains(self)
    }

    var isLatePosition: Bool {
        [.hijack, .cutoff, .button].contains(self)
    }

    var isBlinds: Bool {
        [.smallBlind, .bigBlind].contains(self)
    }
}
