import Foundation

/// Factory to auto-detect and return the appropriate parser for a hand history
class ParserFactory {
    private static let parsers: [HandHistoryParser] = [
        PokerStarsParser()
        // Add more parsers here as they're implemented:
        // GGPokerParser(),
        // PartyPokerParser(),
        // etc.
    ]

    /// Detect which parser can handle the given text
    /// - Parameter text: Hand history text
    /// - Returns: Appropriate parser, or nil if no parser can handle it
    static func parser(for text: String) -> HandHistoryParser? {
        parsers.first { $0.canParse(text) }
    }

    /// Detect parser based on file content
    /// - Parameter url: URL to hand history file
    /// - Returns: Appropriate parser, or nil if no parser can handle it
    static func parser(forFile url: URL) throws -> HandHistoryParser? {
        let text = try String(contentsOf: url, encoding: .utf8)
        return parser(for: text)
    }

    /// Get parser by site name
    /// - Parameter siteName: Name of the poker site
    /// - Returns: Parser for that site, or nil if not found
    static func parser(forSite siteName: String) -> HandHistoryParser? {
        parsers.first { $0.siteName.lowercased() == siteName.lowercased() }
    }

    /// Get all available parsers
    static var availableParsers: [HandHistoryParser] {
        parsers
    }

    /// Get all supported site names
    static var supportedSites: [String] {
        parsers.map { $0.siteName }
    }
}
