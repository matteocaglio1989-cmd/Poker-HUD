import SwiftUI

/// Phase 3 PR4: 13×13 hole-card heat map for the selected hero.
///
/// Standard preflop chart layout:
///   • Pocket pairs on the diagonal
///   • Suited hands above the diagonal
///   • Offsuit hands below the diagonal
///
/// Cell color encodes one of three metrics (toggled via segmented
/// picker):
///   • **Frequency** — how often the hand was dealt (linear)
///   • **Win%** — fraction won at showdown (red↔green diverging at 50%)
///   • **Net/Hand** — average net result per hand (red↔green at 0)
///
/// Empty cells (`handsDealt == 0`) render as flat grey so the user can
/// still see the chart skeleton on a tiny sample.
struct HoleCardHeatMapView: View {
    let matrix: HoleCardMatrix?
    let heroName: String

    @State private var colorMode: ColorMode = .frequency

    enum ColorMode: String, CaseIterable, Identifiable {
        case frequency, winRate, netPerHand
        var id: String { rawValue }
        var title: String {
            switch self {
            case .frequency:  return "Frequency"
            case .winRate:    return "Win %"
            case .netPerHand: return "Net / Hand"
            }
        }
    }

    var body: some View {
        if heroName.isEmpty {
            heroPrompt
        } else if let matrix = matrix, matrix.totalHands > 0 {
            loaded(matrix: matrix)
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
            Text("Select a hero to see hand history heat map")
                .font(.headline)
            Text("Pick a player from the Hero dropdown above. Heat maps need a single player to chart.")
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
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("No hole-card data for \(heroName)")
                .font(.headline)
            Text("Heat maps require dealt hole cards from imported hands. Try widening the filters.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Loaded

    @ViewBuilder
    private func loaded(matrix: HoleCardMatrix) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.grid.3x3.fill")
                    .foregroundStyle(.tint)
                Text("\(matrix.playerName) — \(matrix.totalHands) hands with hole cards")
                    .font(.headline)
                Spacer()
                Picker("", selection: $colorMode) {
                    ForEach(ColorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            .padding(.horizontal)

            grid(matrix: matrix)
                .padding(.horizontal)

            legend
                .padding(.horizontal)
        }
    }

    private func grid(matrix: HoleCardMatrix) -> some View {
        // Compute color scale bounds once per render so the view is
        // self-consistent regardless of filter changes.
        let bounds = colorBounds(matrix: matrix)

        return VStack(spacing: 2) {
            ForEach(0..<13, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<13, id: \.self) { col in
                        let cell = matrix.cellsByPosition[row][col]
                        HoleCardCellView(
                            stats: cell,
                            color: cellColor(cell, mode: colorMode, bounds: bounds)
                        )
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Rectangle().fill(Color.gray.opacity(0.15)).frame(width: 14, height: 14)
                Text("0 samples")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            switch colorMode {
            case .frequency:
                gradientLegend(low: "rare", high: "common", colors: [.gray.opacity(0.2), .blue])
            case .winRate:
                gradientLegend(low: "0%", high: "100%", colors: [.red, .yellow, .green])
            case .netPerHand:
                gradientLegend(low: "−", high: "+", colors: [.red, .gray.opacity(0.5), .green])
            }
            Spacer()
        }
    }

    private func gradientLegend(low: String, high: String, colors: [Color]) -> some View {
        HStack(spacing: 4) {
            Text(low).font(.caption2).foregroundColor(.secondary)
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                .frame(width: 100, height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            Text(high).font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: - Coloring

    private struct ColorBounds {
        let maxFrequency: Int
        let netMin: Double
        let netMax: Double
    }

    private func colorBounds(matrix: HoleCardMatrix) -> ColorBounds {
        var maxFreq = 0
        var minNet = 0.0
        var maxNet = 0.0
        for row in matrix.cellsByPosition {
            for cell in row where cell.handsDealt > 0 {
                if cell.handsDealt > maxFreq { maxFreq = cell.handsDealt }
                if cell.netPerHand < minNet { minNet = cell.netPerHand }
                if cell.netPerHand > maxNet { maxNet = cell.netPerHand }
            }
        }
        return ColorBounds(maxFrequency: maxFreq, netMin: minNet, netMax: maxNet)
    }

    private func cellColor(_ cell: HoleCardCellStats, mode: ColorMode, bounds: ColorBounds) -> Color {
        guard cell.handsDealt > 0 else { return Color.gray.opacity(0.15) }
        switch mode {
        case .frequency:
            let intensity = bounds.maxFrequency > 0
                ? Double(cell.handsDealt) / Double(bounds.maxFrequency)
                : 0
            return Color.blue.opacity(0.15 + 0.65 * intensity)
        case .winRate:
            // 0% = red, 50% = yellow, 100% = green
            let pct = cell.winRatePct
            if pct < 50 {
                return Color.red.opacity(0.30 + 0.60 * (1 - pct / 50))
            } else {
                return Color.green.opacity(0.30 + 0.60 * ((pct - 50) / 50))
            }
        case .netPerHand:
            // negative = red, zero = grey, positive = green; scale by max abs
            let net = cell.netPerHand
            let bound = max(abs(bounds.netMin), abs(bounds.netMax))
            if bound == 0 { return Color.gray.opacity(0.3) }
            if net < 0 {
                return Color.red.opacity(0.30 + 0.60 * min(1.0, abs(net) / bound))
            } else if net > 0 {
                return Color.green.opacity(0.30 + 0.60 * min(1.0, net / bound))
            } else {
                return Color.gray.opacity(0.3)
            }
        }
    }
}

// MARK: - Cell view

private struct HoleCardCellView: View {
    let stats: HoleCardCellStats
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(stats.bucket.label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
            Text(stats.handsDealt > 0 ? "\(stats.handsDealt)" : "")
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(width: 46, height: 38)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .help(tooltipText)
    }

    private var tooltipText: String {
        if stats.handsDealt == 0 {
            return "\(stats.bucket.label) — no hands"
        }
        return String(
            format: "%@: %d hands · win %.0f%% · net %+.2f",
            stats.bucket.label,
            stats.handsDealt,
            stats.winRatePct,
            stats.totalNet
        )
    }
}
