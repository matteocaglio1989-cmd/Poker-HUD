import SwiftUI

/// Phase 3 PR2: post-flop aggression broken down by pre-flop pot type.
/// Shows C-bet and fold-to-C-bet rates for the selected hero, split
/// between single-raised pots (SRP) and 3-bet+ pots (3BP), plus overall
/// turn/river stats.
///
/// Requires a hero to be selected in the filter bar — without one there's
/// no meaningful "whose post-flop aggression" to query. Renders an empty
/// state when no hero is picked or the filter matches zero hands.
struct SituationalStatsView: View {
    let stats: SituationalStats?
    let heroName: String

    var body: some View {
        if heroName.isEmpty {
            heroPrompt
        } else if let stats = stats {
            loaded(stats: stats)
        } else {
            emptyState
        }
    }

    // MARK: - States

    private var heroPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("Select a hero to see situational stats")
                .font(.headline)
            Text("Pick a player from the Hero dropdown above. Situational stats need a single player to analyze.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("No situational data for \(heroName)")
                .font(.headline)
            Text("Try widening the filters or lowering Min Hands. Situational stats need opportunities (hands where the hero was the preflop aggressor) to compute.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    @ViewBuilder
    private func loaded(stats: SituationalStats) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(.tint)
                Text("\(stats.playerName) — \(stats.handsPlayed) hands")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            // Top row: two cards side by side comparing pot types.
            HStack(alignment: .top, spacing: 16) {
                potCard(
                    title: "Single-Raised Pots",
                    subtitle: "1 preflop raise",
                    icon: "1.circle.fill",
                    tint: .blue,
                    cbetPct: stats.cbetFlopSRPPct,
                    cbetHits: stats.cbetFlopSRPHits,
                    cbetOpps: stats.cbetFlopSRPOpps,
                    foldPct: stats.foldCbetFlopSRPPct,
                    foldHits: stats.foldCbetFlopSRPHits,
                    foldOpps: stats.foldCbetFlopSRPOpps
                )
                potCard(
                    title: "3-Bet+ Pots",
                    subtitle: "2+ preflop raises",
                    icon: "3.circle.fill",
                    tint: .orange,
                    cbetPct: stats.cbetFlop3BPPct,
                    cbetHits: stats.cbetFlop3BPHits,
                    cbetOpps: stats.cbetFlop3BPOpps,
                    foldPct: stats.foldCbetFlop3BPPct,
                    foldHits: stats.foldCbetFlop3BPHits,
                    foldOpps: stats.foldCbetFlop3BPOpps
                )
            }
            .padding(.horizontal)

            // Bottom row: turn + river street stats (not split by pot type
            // because the samples get too small to be useful at the
            // per-session level).
            streetCard(
                title: "Turn & River — Overall",
                subtitle: "Not split by pot type",
                rows: [
                    ("C-Bet Turn", stats.cbetTurnPct, stats.cbetTurnHits, stats.cbetTurnOpps),
                    ("C-Bet River", stats.cbetRiverPct, stats.cbetRiverHits, stats.cbetRiverOpps),
                    ("Fold to C-Bet Turn", stats.foldCbetTurnPct, stats.foldCbetTurnHits, stats.foldCbetTurnOpps),
                    ("Fold to C-Bet River", stats.foldCbetRiverPct, stats.foldCbetRiverHits, stats.foldCbetRiverOpps),
                ]
            )
            .padding(.horizontal)
        }
    }

    // MARK: - Card components

    private func potCard(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        cbetPct: Double?,
        cbetHits: Int,
        cbetOpps: Int,
        foldPct: Double?,
        foldHits: Int,
        foldOpps: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline)
            }
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            statRow("C-Bet Flop", pct: cbetPct, hits: cbetHits, opps: cbetOpps, tint: tint)
            statRow("Fold to C-Bet Flop", pct: foldPct, hits: foldHits, opps: foldOpps, tint: tint)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
    }

    private func streetCard(
        title: String,
        subtitle: String,
        rows: [(String, Double?, Int, Int)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
            }
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                statRow(row.0, pct: row.1, hits: row.2, opps: row.3, tint: .secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func statRow(
        _ label: String,
        pct: Double?,
        hits: Int,
        opps: Int,
        tint: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout)
            Spacer()
            if let pct = pct {
                Text(String(format: "%.1f%%", pct))
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(tint)
                Text("(\(hits)/\(opps))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            } else {
                Text("—")
                    .foregroundColor(.secondary)
                    .font(.system(.callout, design: .monospaced))
                Text("(0/0)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
