import Foundation

/// Protocol for parsing hand history files from various poker sites
protocol HandHistoryParser {
    /// The poker site this parser handles
    var siteName: String { get }

    /// Parse a hand history text and extract hand data
    /// - Parameter text: Raw hand history text
    /// - Returns: Array of parsed hands with players and actions
    /// - Throws: ParserError if parsing fails
    func parse(_ text: String) throws -> [ParsedHand]

    /// Detect if this parser can handle the given text
    /// - Parameter text: Hand history text to check
    /// - Returns: True if this parser can handle the text
    func canParse(_ text: String) -> Bool
}

/// A fully parsed hand with all related data
struct ParsedHand {
    var hand: HandData
    let players: [PlayerData]
    let actions: [ActionData]
}

/// Hand metadata
struct HandData {
    let handId: String
    let siteName: String
    let tableName: String
    let gameType: String
    let limitType: String
    let tableSize: Int
    let smallBlind: Double
    let bigBlind: Double
    let ante: Double
    let board: String?
    let potTotal: Double
    let rake: Double
    let playedAt: Date
    let rawText: String
    let tournamentId: String?
    /// Set by ImportEngine after parsing, based on the source filename
    /// and parsed tournament ID. Values: `"CASH"`, `"TOURNAMENT"`,
    /// `"PLAY_MONEY"`. Defaults to `"CASH"` in the parser; the import
    /// engine overrides to `"PLAY_MONEY"` when the filename contains
    /// "Play Money", or to `"TOURNAMENT"` when `tournamentId` is set.
    var moneyType: String = "CASH"
}

/// Player data for a hand
struct PlayerData {
    let username: String
    let seat: Int
    let position: String?
    let holeCards: String?
    let isHero: Bool
    let startingStack: Double
    let totalBet: Double
    let totalWon: Double
    let netResult: Double
    let wentToShowdown: Bool
    let wonAtShowdown: Bool

    // Computed stats (calculated by StatsCalculator)
    var vpip: Bool = false
    var pfr: Bool = false
    var threeBet: Bool = false
    var fourBet: Bool = false
    var coldCall: Bool = false
    var squeeze: Bool = false
    var foldToThreeBet: Bool? = nil
    var cbetFlop: Bool? = nil
    var foldToCbetFlop: Bool? = nil
    var checkRaiseFlop: Bool? = nil
    var cbetTurn: Bool? = nil
    var foldToCbetTurn: Bool? = nil
    var cbetRiver: Bool? = nil
    var foldToCbetRiver: Bool? = nil
    var aggressionFactor: Double? = nil
    var allIn: Bool = false
}

/// Player action data
struct ActionData {
    let username: String
    let street: String
    let actionOrder: Int
    let actionType: String
    let amount: Double
    let potBefore: Double?
    let potAfter: Double?
}

/// Parser errors
enum ParserError: LocalizedError {
    case invalidFormat
    case missingHandId
    case missingGameInfo
    case missingPlayerInfo
    case unsupportedGameType
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid hand history format"
        case .missingHandId:
            return "Hand ID not found"
        case .missingGameInfo:
            return "Game information not found"
        case .missingPlayerInfo:
            return "Player information not found"
        case .unsupportedGameType:
            return "Unsupported game type"
        case .invalidDate:
            return "Invalid date format"
        }
    }
}
