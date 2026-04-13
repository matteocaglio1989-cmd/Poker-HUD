import Foundation

/// Situational breakdown of a single player's post-flop aggression, split
/// by pre-flop pot type (single-raised vs 3-bet+ pots). Produced by
/// `StatsRepository.fetchSituationalStats(...)`.
///
/// Each "stat" is exposed as two numbers: the hit count and the
/// opportunity count. The percentage is a computed getter so views can
/// show "12% (3/25)" without losing the underlying sample size — crucial
/// for early-session small-sample situations where 100% of 1 is very
/// different from 100% of 50.
///
/// Runtime computation: the SQL classifies each hand as single-raised or
/// 3-bet+ by counting `actions` rows with `street='PREFLOP'` and
/// `actionType IN ('RAISE','BET')`. No schema change required — the
/// `cbetFlop` / `foldToCbetFlop` / etc. booleans already stored per-hand
/// are simply conditionally summed by pot type.
struct SituationalStats {
    let playerId: Int64
    let playerName: String
    let handsPlayed: Int

    // MARK: - C-Bet Flop split by pot type

    let cbetFlopSRPHits: Int
    let cbetFlopSRPOpps: Int
    let cbetFlop3BPHits: Int
    let cbetFlop3BPOpps: Int

    // MARK: - Fold to C-Bet Flop split by pot type

    let foldCbetFlopSRPHits: Int
    let foldCbetFlopSRPOpps: Int
    let foldCbetFlop3BPHits: Int
    let foldCbetFlop3BPOpps: Int

    // MARK: - Overall street-by-street (not split)

    let cbetTurnHits: Int
    let cbetTurnOpps: Int
    let cbetRiverHits: Int
    let cbetRiverOpps: Int
    let foldCbetTurnHits: Int
    let foldCbetTurnOpps: Int
    let foldCbetRiverHits: Int
    let foldCbetRiverOpps: Int

    // MARK: - Computed percentages (nil when no opportunities)

    var cbetFlopSRPPct: Double? { pct(cbetFlopSRPHits, cbetFlopSRPOpps) }
    var cbetFlop3BPPct: Double? { pct(cbetFlop3BPHits, cbetFlop3BPOpps) }
    var foldCbetFlopSRPPct: Double? { pct(foldCbetFlopSRPHits, foldCbetFlopSRPOpps) }
    var foldCbetFlop3BPPct: Double? { pct(foldCbetFlop3BPHits, foldCbetFlop3BPOpps) }
    var cbetTurnPct: Double? { pct(cbetTurnHits, cbetTurnOpps) }
    var cbetRiverPct: Double? { pct(cbetRiverHits, cbetRiverOpps) }
    var foldCbetTurnPct: Double? { pct(foldCbetTurnHits, foldCbetTurnOpps) }
    var foldCbetRiverPct: Double? { pct(foldCbetRiverHits, foldCbetRiverOpps) }

    private func pct(_ hits: Int, _ opps: Int) -> Double? {
        guard opps > 0 else { return nil }
        return Double(hits) * 100.0 / Double(opps)
    }
}
