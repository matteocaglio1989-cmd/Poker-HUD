import SwiftUI

/// Compact stat display panel for a single opponent
struct StandardHUDView: View {
    let playerName: String
    let stats: PlayerStats?
    let configuration: HUDConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Player name + type badge
            HStack(spacing: 4) {
                Text(playerName)
                    .font(.system(size: configuration.fontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                if let stats = stats, configuration.showPlayerType {
                    PlayerTypeBadge(type: stats.playerType, fontSize: configuration.fontSize - 2)
                }
            }

            Divider()
                .background(Color.white.opacity(0.3))

            if let stats = stats {
                // Row 1: VPIP / PFR / 3Bet
                HStack(spacing: 0) {
                    statCell(value: stats.vpip, color: configuration.colorThresholds.colorForVPIP(stats.vpip))
                    Text("/").foregroundColor(.gray).font(.system(size: configuration.fontSize - 1, design: .monospaced))
                    statCell(value: stats.pfr, color: configuration.colorThresholds.colorForPFR(stats.pfr))
                    Text("/").foregroundColor(.gray).font(.system(size: configuration.fontSize - 1, design: .monospaced))
                    statCell(value: stats.threeBet, color: configuration.colorThresholds.colorFor3Bet(stats.threeBet))
                    Spacer()
                    statLabel("AF", value: String(format: "%.1f", stats.aggressionFactor),
                              color: configuration.colorThresholds.colorForAF(stats.aggressionFactor))
                }

                // Row 2: WTSD / W$SD
                HStack(spacing: 0) {
                    statLabel("WT", value: String(format: "%.0f", stats.wtsd), color: .white)
                    Text(" ").font(.system(size: configuration.fontSize - 1))
                    statLabel("W$", value: String(format: "%.0f", stats.wsd), color: .white)
                    Spacer()
                    Text("\(stats.handsPlayed)h")
                        .font(.system(size: configuration.fontSize - 1, design: .monospaced))
                        .foregroundColor(.gray)
                }
            } else {
                Text("No data")
                    .font(.system(size: configuration.fontSize - 1, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
        .padding(6)
        .background(Color.black.opacity(configuration.opacity))
        .cornerRadius(6)
        .frame(width: 170)
    }

    private func statCell(value: Double, color: Color) -> some View {
        Text(String(format: "%.0f", value))
            .font(.system(size: configuration.fontSize, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
    }

    private func statLabel(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 1) {
            Text(label + ":")
                .font(.system(size: configuration.fontSize - 1, design: .monospaced))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: configuration.fontSize, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

/// Color-coded player type badge
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
