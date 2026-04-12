import SwiftUI

/// Full stat breakdown shown when the user double-clicks a HUD label.
/// Organised into four sections (Preflop / Postflop / Showdown /
/// Results) following the Poker Copilot HUD statistics layout. All
/// values come from the existing `PlayerStats` model — no extra DB
/// queries needed.
///
/// Double-click again (or tap the collapse hint) to shrink back to
/// the compact `StandardHUDView`.
struct ExpandedHUDView: View {
    let playerName: String
    let stats: PlayerStats?
    let configuration: HUDConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Header: name + type badge + hand count
            HStack(spacing: 4) {
                Text(playerName)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let stats = stats {
                    PlayerTypeBadge(type: stats.playerType, fontSize: 8)
                    Text("\(stats.handsPlayed)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            thinDivider

            if let stats = stats {
                // ── Preflop ──
                sectionHeader("Preflop")
                statRow("VPIP",    pct: stats.vpip)
                statRow("PFR",     pct: stats.pfr)
                statRow("3-Bet",   pct: stats.threeBet)
                statRow("4-Bet",   pct: stats.fourBet)
                statRow("F3B",     pct: stats.foldToThreeBet)
                statRow("CC",      pct: stats.coldCall)
                statRow("SQZ",     pct: stats.squeeze)

                thinDivider

                // ── Postflop ──
                sectionHeader("Postflop")
                statRow("CBet F",  pct: stats.cbetFlop)
                statRow("CBet T",  pct: stats.cbetTurn)
                statRow("CBet R",  pct: stats.cbetRiver)
                statRow("F-CB F",  pct: stats.foldToCbetFlop)
                statRow("F-CB T",  pct: stats.foldToCbetTurn)
                statRow("F-CB R",  pct: stats.foldToCbetRiver)
                statRow("AF",      val: String(format: "%.1f", stats.aggressionFactor))
                statRow("Agg%",    pct: stats.aggressionPercentage)

                thinDivider

                // ── Showdown ──
                sectionHeader("Showdown")
                statRow("WTSD",    pct: stats.wtsd)
                statRow("W$SD",    pct: stats.wsd)

                thinDivider

                // ── Results ──
                sectionHeader("Results")
                coloredRow("BB/100", value: String(format: "%+.1f", stats.bb100),
                           color: stats.bb100 >= 0 ? .green : .red)
                coloredRow("Won",    value: String(format: "%+.2f", stats.totalWon),
                           color: stats.totalWon >= 0 ? .green : .red)
            } else {
                Text("No data yet")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
            }

            // Collapse hint
            Text("double-click to collapse")
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.3))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
        .padding(6)
        .background(Color.black.opacity(configuration.opacity))
        .cornerRadius(6)
        .frame(width: 200)
    }

    // MARK: - Helpers

    private var thinDivider: some View {
        Divider().background(Color.white.opacity(0.2))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.yellow)
            .padding(.top, 1)
    }

    private func statRow(_ label: String, pct: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
            Spacer()
            Text(String(format: "%.1f%%", pct))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
        }
    }

    private func statRow(_ label: String, val: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
            Spacer()
            Text(val)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
        }
    }

    private func coloredRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
    }
}
