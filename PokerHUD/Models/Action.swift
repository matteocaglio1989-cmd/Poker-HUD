import Foundation
import GRDB

struct Action: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var handId: Int64
    var playerId: Int64
    var street: String  // PREFLOP, FLOP, TURN, RIVER
    var actionOrder: Int
    var actionType: String  // FOLD, CHECK, CALL, BET, RAISE, ALL_IN
    var amount: Double
    var potBefore: Double?
    var potAfter: Double?

    static let databaseTableName = "actions"

    enum Columns: String, ColumnExpression {
        case id, handId, playerId, street, actionOrder
        case actionType, amount, potBefore, potAfter
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Action: Identifiable {}

extension Action {
    static let hand = belongsTo(Hand.self)
    static let player = belongsTo(Player.self)
}

enum Street: String, CaseIterable {
    case preflop = "PREFLOP"
    case flop = "FLOP"
    case turn = "TURN"
    case river = "RIVER"

    var displayName: String {
        rawValue.capitalized
    }

    var order: Int {
        switch self {
        case .preflop: return 0
        case .flop: return 1
        case .turn: return 2
        case .river: return 3
        }
    }
}

enum ActionType: String, CaseIterable {
    case fold = "FOLD"
    case check = "CHECK"
    case call = "CALL"
    case bet = "BET"
    case raise = "RAISE"
    case allIn = "ALL_IN"

    var displayName: String {
        switch self {
        case .fold: return "Fold"
        case .check: return "Check"
        case .call: return "Call"
        case .bet: return "Bet"
        case .raise: return "Raise"
        case .allIn: return "All-In"
        }
    }

    var isAggressive: Bool {
        [.bet, .raise, .allIn].contains(self)
    }

    var isPassive: Bool {
        [.check, .call].contains(self)
    }
}
