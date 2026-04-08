import SwiftUI

/// Phase 3 PR3: opponent deep-dive sheet, presented from a player row tap
/// in `ReportsView`'s `PlayerStatsTable`. Reuses `SituationalStatsView`
/// from PR2 to render the opponent's situational breakdown so a poker
/// player can answer "how does this villain play in 3-bet pots?" without
/// switching tabs.
///
/// Three sections:
///   1. Header card — name, sample size, player type, BB/100
///   2. Headline preflop stats grid
///   3. Embedded SituationalStatsView with the opponent's flop / turn /
///      river splits (loaded lazily on appear)
struct OpponentDetailView: View {
    let opponent: PlayerStats
    let filters: StatFilters

    @Environment(\.dismiss) private var dismiss
    @State private var situational: SituationalStats?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    preflopGrid

                    if isLoading {
                        ProgressView("Loading situational stats…")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        SituationalStatsView(
                            stats: situational,
                            heroName: opponent.playerName
                        )
                    }
                }
                .padding(.vertical)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .task {
            await loadSituational()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(opponent.playerName)
                        .font(.title2)
                        .fontWeight(.bold)
                    PlayerTypeBadge(type: opponent.playerType, fontSize: 11)
                }
                Text("\(opponent.handsPlayed) hands sample")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("BB/100")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%+.2f", opponent.bb100))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(opponent.bb100 >= 0 ? .green : .red)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Preflop stat grid

    private var preflopGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preflop")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), spacing: 12)],
                spacing: 12
            ) {
                statTile("VPIP",       value: opponent.vpip)
                statTile("PFR",        value: opponent.pfr)
                statTile("3-Bet",      value: opponent.threeBet)
                statTile("4-Bet",      value: opponent.fourBet)
                statTile("Fold to 3B", value: opponent.foldToThreeBet)
                statTile("Cold Call",  value: opponent.coldCall)
                statTile("Squeeze",    value: opponent.squeeze)
                statTile("AF",         value: opponent.aggressionFactor, isPercent: false, decimals: 1)
                statTile("WTSD",       value: opponent.wtsd)
                statTile("W$SD",       value: opponent.wsd)
            }
            .padding(.horizontal)
        }
    }

    private func statTile(
        _ label: String,
        value: Double,
        isPercent: Bool = true,
        decimals: Int = 1
    ) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(isPercent
                 ? String(format: "%.\(decimals)f%%", value)
                 : String(format: "%.\(decimals)f", value))
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    // MARK: - Loading

    private func loadSituational() async {
        isLoading = true
        defer { isLoading = false }
        do {
            situational = try StatsRepository().fetchSituationalStats(
                playerName: opponent.playerName,
                filters: filters
            )
        } catch {
            print("[OpponentDetailView] failed to load situational stats: \(error)")
            situational = nil
        }
    }
}
