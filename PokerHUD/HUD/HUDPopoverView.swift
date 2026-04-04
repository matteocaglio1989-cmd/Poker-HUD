import SwiftUI

/// Detailed stat breakdown shown when clicking a HUD panel
struct HUDPopoverView: View {
    let playerName: String
    let stats: PlayerStats
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(playerName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                PlayerTypeBadge(type: stats.playerType, fontSize: 10)
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }

            Divider().background(Color.white.opacity(0.3))

            // Sample size
            Text("\(stats.handsPlayed) hands tracked")
                .font(.system(size: 11))
                .foregroundColor(.gray)

            // Preflop section
            sectionHeader("Preflop")
            statRow("VPIP", value: String(format: "%.1f%%", stats.vpip))
            statRow("PFR", value: String(format: "%.1f%%", stats.pfr))
            statRow("3-Bet", value: String(format: "%.1f%%", stats.threeBet))
            statRow("4-Bet", value: String(format: "%.1f%%", stats.fourBet))
            statRow("Fold to 3-Bet", value: String(format: "%.1f%%", stats.foldToThreeBet))
            statRow("Cold Call", value: String(format: "%.1f%%", stats.coldCall))

            Divider().background(Color.white.opacity(0.2))

            // Postflop section
            sectionHeader("Postflop")
            statRow("Aggression Factor", value: String(format: "%.2f", stats.aggressionFactor))
            statRow("C-Bet Flop", value: String(format: "%.1f%%", stats.cbetFlop))
            statRow("C-Bet Turn", value: String(format: "%.1f%%", stats.cbetTurn))
            statRow("Fold to C-Bet", value: String(format: "%.1f%%", stats.foldToCbetFlop))

            Divider().background(Color.white.opacity(0.2))

            // Showdown section
            sectionHeader("Showdown")
            statRow("WTSD", value: String(format: "%.1f%%", stats.wtsd))
            statRow("W$SD", value: String(format: "%.1f%%", stats.wsd))

            Divider().background(Color.white.opacity(0.2))

            // Results
            sectionHeader("Results")
            statRow("BB/100", value: String(format: "%.2f", stats.bb100),
                    valueColor: stats.bb100 >= 0 ? .green : .red)
            statRow("Total Won", value: String(format: "$%.2f", stats.totalWon),
                    valueColor: stats.totalWon >= 0 ? .green : .red)
        }
        .padding(10)
        .background(Color.black.opacity(0.9))
        .cornerRadius(8)
        .frame(width: 220)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.yellow)
    }

    private func statRow(_ label: String, value: String, valueColor: Color = .white) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(valueColor)
        }
    }
}
