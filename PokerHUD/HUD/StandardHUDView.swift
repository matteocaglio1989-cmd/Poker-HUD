import SwiftUI

/// Minimalist HUD panel: player name on top, a single big `25/15/1`
/// (VPIP/PFR/3Bet) line underneath. Two rows total.
///
/// Intentionally tiny — the user wanted the in-game overlay to show
/// only the three numbers that matter during a hand, at double the
/// normal font size, with no secondary rows cluttering the view.
/// Fold-to-cbet, squeeze, aggression factor, showdown stats, hand
/// count, and the player-type badge all still live in
/// `OpponentDetailView` one click away in the Reports tab.
struct StandardHUDView: View {
    let playerName: String
    let stats: PlayerStats?
    let configuration: HUDConfiguration

    private var bigFontSize: CGFloat {
        CGFloat(configuration.fontSize) * 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Row 1: player name only
            Text(playerName)
                .font(.system(size: CGFloat(configuration.fontSize), weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .background(Color.white.opacity(0.3))

            // Row 2: big VPIP / PFR / 3Bet
            if let stats = stats {
                HStack(spacing: 2) {
                    bigStatCell(value: stats.vpip, color: configuration.colorThresholds.colorForVPIP(stats.vpip))
                    Text("/").foregroundColor(.gray)
                        .font(.system(size: bigFontSize, weight: .semibold, design: .monospaced))
                    bigStatCell(value: stats.pfr, color: configuration.colorThresholds.colorForPFR(stats.pfr))
                    Text("/").foregroundColor(.gray)
                        .font(.system(size: bigFontSize, weight: .semibold, design: .monospaced))
                    bigStatCell(value: stats.threeBet, color: configuration.colorThresholds.colorFor3Bet(stats.threeBet))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("—")
                    .font(.system(size: bigFontSize, weight: .semibold, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(6)
        .background(Color.black.opacity(configuration.opacity))
        .cornerRadius(6)
        .frame(width: 170)
    }

    private func bigStatCell(value: Double, color: Color) -> some View {
        Text(String(format: "%.0f", value))
            .font(.system(size: bigFontSize, weight: .bold, design: .monospaced))
            .foregroundColor(color)
    }
}

/// Color-coded player type badge. No longer used by `StandardHUDView`
/// (the minimalist redesign dropped it) but still referenced by
/// `ReportsView.HeroSummaryCard`, `OpponentDetailView`, and
/// `HUDPopoverView`, so the declaration stays.
struct PlayerTypeBadge: View {
    let type: PlayerType
    let fontSize: CGFloat

    var body: some View {
        Text(type.rawValue.uppercased())
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(colorForType.opacity(0.8))
            .cornerRadius(3)
    }

    private var colorForType: Color {
        switch type {
        case .tag: return .green
        case .lag: return .blue
        case .nit: return .red
        case .fish: return .orange
        case .rock: return .purple
        case .maniac: return .pink
        case .unknown: return .gray
        }
    }
}
