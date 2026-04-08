import Foundation

/// Phase 3 PR4: parses raw hole-card strings (PokerStars format like
/// `"Ah Kd"`) into the canonical 169-class hand grid used by the
/// `HoleCardHeatMapView`.
///
/// The 169-class grid is the standard preflop poker chart:
///   • 13 pocket pairs       (AA, KK, ..., 22)
///   • 78 suited hands       (AKs, AQs, ..., 32s)
///   • 78 offsuit hands      (AKo, AQo, ..., 32o)
///
/// Indexed by `(row, col)` where row = higher rank's index, col = lower
/// rank's index in the canonical A→2 ordering. Pairs sit on the
/// diagonal, suited hands above it, offsuit below — that's the
/// universal "preflop chart" layout every poker player recognises.
enum HoleCardClassifier {
    /// Canonical rank ordering. Index 0 = strongest (Ace), 12 = weakest (2).
    /// `Self.rankOrder[i]` is the symbol for column / row `i` in the grid.
    static let rankOrder: [Character] = ["A", "K", "Q", "J", "T", "9", "8", "7", "6", "5", "4", "3", "2"]

    /// Parse a hole-card string into a `HoleCardBucket`. Returns nil for
    /// malformed input or single-card hands. Accepts:
    ///   • Two-card formats: `"Ah Kd"`, `"AhKd"`, `"AdAh"`
    ///   • Suit chars: `h d c s` (case-insensitive)
    ///   • Rank chars: `2-9 T J Q K A` (case-insensitive)
    static func bucket(for holeCards: String) -> HoleCardBucket? {
        let trimmed = holeCards.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Strip whitespace, take exactly 4 chars (rank+suit×2).
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count == 4 else { return nil }
        let chars = Array(compact)
        guard let r1 = parseRank(chars[0]),
              let s1 = parseSuit(chars[1]),
              let r2 = parseRank(chars[2]),
              let s2 = parseSuit(chars[3]) else { return nil }

        let i1 = rankIndex(r1)
        let i2 = rankIndex(r2)
        let highIndex = min(i1, i2)
        let lowIndex = max(i1, i2)
        let suited = (s1 == s2)

        return HoleCardBucket(
            highRankIndex: highIndex,
            lowRankIndex: lowIndex,
            isSuited: suited
        )
    }

    /// Build all 169 buckets in row-major order. Used to seed the matrix
    /// so the view always renders a full grid even if some cells have
    /// zero samples.
    static func allBuckets() -> [HoleCardBucket] {
        var buckets: [HoleCardBucket] = []
        for high in 0..<13 {
            for low in 0..<13 {
                if high == low {
                    buckets.append(HoleCardBucket(highRankIndex: high, lowRankIndex: low, isSuited: false))
                } else if high < low {
                    // Above the diagonal → suited
                    buckets.append(HoleCardBucket(highRankIndex: high, lowRankIndex: low, isSuited: true))
                } else {
                    // Below the diagonal → offsuit (swap to canonical order)
                    buckets.append(HoleCardBucket(highRankIndex: low, lowRankIndex: high, isSuited: false))
                }
            }
        }
        return buckets
    }

    // MARK: - Private

    private static func parseRank(_ c: Character) -> Character? {
        let upper = Character(c.uppercased())
        return rankOrder.contains(upper) ? upper : nil
    }

    private static func parseSuit(_ c: Character) -> Character? {
        let lower = Character(c.lowercased())
        return ["h", "d", "c", "s"].contains(lower) ? lower : nil
    }

    private static func rankIndex(_ rank: Character) -> Int {
        rankOrder.firstIndex(of: rank) ?? 12
    }
}
