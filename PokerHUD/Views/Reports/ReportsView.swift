import SwiftUI
import Charts

struct ReportsView: View {
    @State private var playerStats: [PlayerStats] = []
    @State private var isLoading = false
    @State private var selectedTimeRange: TimeRange = .allTime
    @State private var minHands = 10

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Cash Game Reports")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Analyze your poker statistics")
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Filters
                    HStack {
                        Picker("Time Range", selection: $selectedTimeRange) {
                            ForEach(TimeRange.allCases) { range in
                                Text(range.title).tag(range)
                            }
                        }
                        .pickerStyle(.menu)

                        Stepper("Min Hands: \(minHands)", value: $minHands, in: 1...1000, step: 10)
                    }
                }
                .padding()

                // Loading State
                if isLoading {
                    ProgressView("Loading statistics...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }

                // Stats Table
                if !playerStats.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Player Statistics")
                            .font(.headline)
                            .padding(.horizontal)

                        PlayerStatsTable(stats: playerStats)
                    }
                } else if !isLoading {
                    EmptyReportView()
                }
            }
        }
        .task {
            await loadStats()
        }
        .onChange(of: selectedTimeRange) { _, _ in
            Task { await loadStats() }
        }
        .onChange(of: minHands) { _, _ in
            Task { await loadStats() }
        }
    }

    private func loadStats() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let calculator = StatsCalculator()
            let filters = createFilters(for: selectedTimeRange)
            playerStats = try calculator.getAllPlayerStats(minHands: minHands, filters: filters)
        } catch {
            print("Error loading stats: \(error)")
        }
    }

    private func createFilters(for range: TimeRange) -> StatFilters {
        var filters = StatFilters()
        let now = Date()

        switch range {
        case .today:
            filters.fromDate = Calendar.current.startOfDay(for: now)
        case .week:
            filters.fromDate = Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .month:
            filters.fromDate = Calendar.current.date(byAdding: .month, value: -1, to: now)
        case .year:
            filters.fromDate = Calendar.current.date(byAdding: .year, value: -1, to: now)
        case .allTime:
            break
        }

        return filters
    }
}

struct PlayerStatsTable: View {
    let stats: [PlayerStats]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Player")
                    .frame(width: 150, alignment: .leading)
                Text("Hands")
                    .frame(width: 60, alignment: .trailing)
                Text("VPIP")
                    .frame(width: 60, alignment: .trailing)
                Text("PFR")
                    .frame(width: 60, alignment: .trailing)
                Text("3Bet")
                    .frame(width: 60, alignment: .trailing)
                Text("AF")
                    .frame(width: 60, alignment: .trailing)
                Text("WTSD")
                    .frame(width: 60, alignment: .trailing)
                Text("W$SD")
                    .frame(width: 60, alignment: .trailing)
                Text("BB/100")
                    .frame(width: 80, alignment: .trailing)
                Text("Type")
                    .frame(width: 80, alignment: .leading)
            }
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(Color.secondary.opacity(0.1))

            Divider()

            // Rows
            ForEach(stats) { stat in
                PlayerStatsRow(stat: stat)
                Divider()
            }
        }
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct PlayerStatsRow: View {
    let stat: PlayerStats

    var body: some View {
        HStack {
            Text(stat.playerName)
                .frame(width: 150, alignment: .leading)
                .lineLimit(1)
            Text("\(stat.handsPlayed)")
                .frame(width: 60, alignment: .trailing)
            Text(String(format: "%.1f", stat.vpip))
                .frame(width: 60, alignment: .trailing)
                .foregroundColor(colorForVPIP(stat.vpip))
            Text(String(format: "%.1f", stat.pfr))
                .frame(width: 60, alignment: .trailing)
                .foregroundColor(colorForPFR(stat.pfr))
            Text(String(format: "%.1f", stat.threeBet))
                .frame(width: 60, alignment: .trailing)
            Text(String(format: "%.1f", stat.aggressionFactor))
                .frame(width: 60, alignment: .trailing)
            Text(String(format: "%.1f", stat.wtsd))
                .frame(width: 60, alignment: .trailing)
            Text(String(format: "%.1f", stat.wsd))
                .frame(width: 60, alignment: .trailing)
            Text(String(format: "%.2f", stat.bb100))
                .frame(width: 80, alignment: .trailing)
                .foregroundColor(stat.bb100 >= 0 ? .green : .red)
            Text(stat.playerType.rawValue)
                .frame(width: 80, alignment: .leading)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(colorForPlayerType(stat.playerType).opacity(0.2))
                .cornerRadius(4)
        }
        .font(.system(.body, design: .monospaced))
        .padding(.vertical, 8)
        .padding(.horizontal)
    }

    private func colorForVPIP(_ vpip: Double) -> Color {
        if vpip < 15 { return .red }
        if vpip < 25 { return .orange }
        if vpip < 35 { return .green }
        return .blue
    }

    private func colorForPFR(_ pfr: Double) -> Color {
        if pfr < 10 { return .red }
        if pfr < 18 { return .orange }
        if pfr < 25 { return .green }
        return .blue
    }

    private func colorForPlayerType(_ type: PlayerType) -> Color {
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

struct EmptyReportView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No statistics available")
                .font(.headline)
            Text("Import hand histories to see your poker stats")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

enum TimeRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Last 7 Days"
    case month = "Last 30 Days"
    case year = "Last Year"
    case allTime = "All Time"

    var id: String { rawValue }
    var title: String { rawValue }
}
