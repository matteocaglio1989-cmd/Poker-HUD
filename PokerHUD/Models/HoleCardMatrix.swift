import Foundation

/// One of the 169 preflop hand classes. Pairs have `highRankIndex ==
/// lowRankIndex` and are neither suited nor offsuit (`isSuited` is
/// arbitrarily false for pairs). For non-pairs, `highRankIndex` is
/// always strictly less than `lowRankIndex` in the A→2 ordering, and
/// `isSuited` distinguishes the two halves of the grid.
struct HoleCardBucket: Hashable {
    let highRankIndex: Int   // 0 = A, 12 = 2
    let lowRankIndex: Int    // 0 = A, 12 = 2
    let isSuited: Bool

    var isPair: Bool { highRankIndex == lowRankIndex }

    /// Cell label as it appears on a poker preflop chart, e.g. `"AA"`,
    /// `"AKs"`, `"AKo"`, `"72o"`.
    var label: String {
        let high = HoleCardClassifier.rankOrder[highRankIndex]
        let low = HoleCardClassifier.rankOrder[lowRankIndex]
        if isPair { return "\(high)\(low)" }
        return "\(high)\(low)\(isSuited ? "s" : "o")"
    }

    /// `(row, col)` for placement in the 13×13 grid. By convention pairs
    /// sit on the diagonal, suited hands above it, offsuit hands below
    /// — matching how every published poker chart is laid out.
    var gridPosition: (row: Int, col: Int) {
        if isPair {
            return (highRankIndex, highRankIndex)
        } else if isSuited {
            // Above diagonal: row = higher (smaller index), col = lower
            return (highRankIndex, lowRankIndex)
        } else {
            // Below diagonal: row = lower (larger index), col = higher
            return (lowRankIndex, highRankIndex)
        }
    }
}

/// Aggregated stats for one of the 169 buckets, computed by
/// `StatsRepository.fetchHoleCardMatrix(...)`.
struct HoleCardCellStats: Hashable {
    let bucket: HoleCardBucket
    let handsDealt: Int
    let handsWon: Int       // hands won at showdown
    let totalNet: Double    // sum of netResult across all hands in this bucket

    var winRatePct: Double {
        guard handsDealt > 0 else { return 0 }
        return Double(handsWon) * 100.0 / Double(handsDealt)
    }

    /// Net result per hand, in the same units as `Hand.bigBlind`. Useful
    /// for color-coding the heat map by EV.
    var netPerHand: Double {
        guard handsDealt > 0 else { return 0 }
        return totalNet / Double(handsDealt)
    }
}

/// Container for the full 169-cell matrix. The cells are always
/// 169 entries — buckets without samples have `handsDealt == 0` so
/// the view can render a uniform grid regardless of sample size.
struct HoleCardMatrix {
    let playerName: String
    let totalHands: Int
    /// Indexed by `(row, col)` from `bucket.gridPosition`. Always
    /// 13×13 = 169 cells, populated for every bucket even when
    /// `handsDealt == 0`.
    let cellsByPosition: [[HoleCardCellStats]]

    static func empty(playerName: String) -> HoleCardMatrix {
        // Build a 13×13 grid of zero-sample cells using the canonical
        // bucket ordering. Used as the "no data" rendering target.
        var rows: [[HoleCardCellStats]] = Array(
            repeating: Array(
                repeating: HoleCardCellStats(
                    bucket: HoleCardBucket(highRankIndex: 0, lowRankIndex: 0, isSuited: false),
                    handsDealt: 0,
                    handsWon: 0,
                    totalNet: 0
                ),
                count: 13
            ),
            count: 13
        )
        for bucket in HoleCardClassifier.allBuckets() {
            let pos = bucket.gridPosition
            rows[pos.row][pos.col] = HoleCardCellStats(
                bucket: bucket,
                handsDealt: 0,
                handsWon: 0,
                totalNet: 0
            )
        }
        return HoleCardMatrix(playerName: playerName, totalHands: 0, cellsByPosition: rows)
    }
}
