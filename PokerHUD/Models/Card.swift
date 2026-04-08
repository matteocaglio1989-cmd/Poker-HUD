import Foundation

/// Phase 4 PR2: minimal value type for one playing card. Used by the
/// visual replayer (`PlayingCardView`, `PokerTableView`) to render board
/// and hole cards. Intentionally separate from `HoleCardClassifier` —
/// that file's `parseRank` / `parseSuit` helpers are private and the
/// classifier itself is shaped around the 169-class preflop chart, not
/// individual cards.
///
/// Cards are parsed from the PokerStars textual format (`"Ah"`, `"Td"`,
/// `"2c"`, `"Ks"`). Both rank and suit are case-insensitive on input but
/// stored canonically (rank uppercase, suit lowercase) so equality and
/// hashing are well-defined.
struct Card: Hashable, Identifiable {
    let rank: Rank
    let suit: Suit

    var id: String { "\(rank.symbol)\(suit.symbol)" }

    init(rank: Rank, suit: Suit) {
        self.rank = rank
        self.suit = suit
    }

    /// Parse a 2-character string like `"Ah"` or `"Td"`. Returns nil for
    /// any malformed input.
    static func parse(_ string: String) -> Card? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 2 else { return nil }
        let chars = Array(trimmed)
        guard let rank = Rank(symbol: chars[0]),
              let suit = Suit(symbol: chars[1]) else { return nil }
        return Card(rank: rank, suit: suit)
    }

    /// Convenience: parse a space-separated card list like
    /// `"Ah Kd 7s 2c Jh"` (the format used by `Hand.board` and
    /// `HandPlayer.holeCards`).
    static func parseList(_ string: String) -> [Card] {
        string
            .split(separator: " ")
            .compactMap { Card.parse(String($0)) }
    }
}

enum Rank: Int, CaseIterable, Hashable {
    case two = 2, three, four, five, six, seven, eight, nine, ten
    case jack, queen, king, ace

    /// Single-character display symbol (`A`, `K`, `Q`, `J`, `T`, `9`...`2`).
    var symbol: String {
        switch self {
        case .ace:   return "A"
        case .king:  return "K"
        case .queen: return "Q"
        case .jack:  return "J"
        case .ten:   return "T"
        case .nine:  return "9"
        case .eight: return "8"
        case .seven: return "7"
        case .six:   return "6"
        case .five:  return "5"
        case .four:  return "4"
        case .three: return "3"
        case .two:   return "2"
        }
    }

    init?(symbol: Character) {
        switch Character(String(symbol).uppercased()) {
        case "A": self = .ace
        case "K": self = .king
        case "Q": self = .queen
        case "J": self = .jack
        case "T": self = .ten
        case "9": self = .nine
        case "8": self = .eight
        case "7": self = .seven
        case "6": self = .six
        case "5": self = .five
        case "4": self = .four
        case "3": self = .three
        case "2": self = .two
        default:  return nil
        }
    }
}

enum Suit: String, CaseIterable, Hashable {
    case hearts   = "h"
    case diamonds = "d"
    case clubs    = "c"
    case spades   = "s"

    /// Lowercase suit letter, matching the PokerStars format.
    var symbol: String { rawValue }

    /// Unicode glyph used for visual display (red ♥♦, black ♣♠).
    var glyph: String {
        switch self {
        case .hearts:   return "♥"
        case .diamonds: return "♦"
        case .clubs:    return "♣"
        case .spades:   return "♠"
        }
    }

    /// `true` for red suits (hearts, diamonds), false otherwise.
    var isRed: Bool {
        self == .hearts || self == .diamonds
    }

    init?(symbol: Character) {
        switch Character(String(symbol).lowercased()) {
        case "h": self = .hearts
        case "d": self = .diamonds
        case "c": self = .clubs
        case "s": self = .spades
        default:  return nil
        }
    }
}
