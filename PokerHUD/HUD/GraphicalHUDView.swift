import SwiftUI

/// Ring-based graphical HUD showing player tendencies at a glance
struct GraphicalHUDView: View {
    let playerName: String
    let stats: PlayerStats?
    let configuration: HUDConfiguration

    var body: some View {
        VStack(spacing: 2) {
            // Rings
            ZStack {
                if let stats = stats {
                    // Outer ring: VPIP (how often they play)
                    RingView(
                        progress: stats.vpip / 100,
                        color: configuration.colorThresholds.colorForVPIP(stats.vpip),
                        lineWidth: 5
                    )
                    .frame(width: 44, height: 44)

                    // Inner ring: PFR (how aggressively)
                    RingView(
                        progress: stats.pfr / 100,
                        color: configuration.colorThresholds.colorForPFR(stats.pfr),
                        lineWidth: 4
                    )
                    .frame(width: 32, height: 32)

                    // Center: AF dot
                    Circle()
                        .fill(configuration.colorThresholds.colorForAF(stats.aggressionFactor))
                        .frame(width: 10, height: 10)
                } else {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 44, height: 44)
                    Text("?")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }

            // Hands count
            if let stats = stats {
                Text("\(stats.handsPlayed)h")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray)
            }

            // Stat line: V/P/3B
            if let stats = stats {
                Text(String(format: "%.0f/%.0f/%.0f", stats.vpip, stats.pfr, stats.threeBet))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }

            // Player name (truncated)
            Text(playerName.prefix(10))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
        }
        .padding(5)
        .background(Color.black.opacity(configuration.opacity))
        .cornerRadius(8)
        .frame(width: 70)
    }
}

/// A partial ring/arc view showing a percentage
struct RingView: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)

            // Progress arc
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
