import SwiftUI
import GRDB

struct ReportsView: View {
    @EnvironmentObject var appState: AppState
    @State private var playerStats: [PlayerStats] = []
    @State private var isLoading = false
    @State private var selectedTimeRange: TimeRange = .allTime
    @State private var minHands = 1
    @State private var errorMessage: String? = nil
    @State private var heroPlayerName: String = ""
    @State private var availableHeroes: [String] = []

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
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack {
                            if !availableHeroes.isEmpty {
                                Picker("Hero", selection: $heroPlayerName) {
                                    Text("All Players").tag("")
                                    ForEach(availableHeroes, id: \.self) { name in
                                        Text(name).tag(name)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 200)
                            }

                            Picker("Time Range", selection: $selectedTimeRange) {
                                ForEach(TimeRange.allCases) { range in
                                    Text(range.title).tag(range)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Stepper("Min Hands: \(minHands)", value: $minHands, in: 1...1000, step: 5)
                    }
                }
                .padding()

                // Error display
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }

                // Hero summary card
                if !heroPlayerName.isEmpty, let heroStats = playerStats.first(where: { $0.playerName == heroPlayerName }) {
                    HeroSummaryCard(stats: heroStats)
                        .padding(.horizontal)
                }

                // Loading State
                if isLoading {
                    ProgressView("Loading statistics...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }

                // Stats Table
                if !playerStats.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Player Statistics (\(playerStats.count) players)")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.horizontal)

                        PlayerStatsTable(stats: playerStats, heroName: heroPlayerName)
                    }
                } else if !isLoading {
                    EmptyReportView()
                }
            }
        }
        .task {
            await loadHeroes()
            await loadStats()
        }
        .onChange(of: selectedTimeRange) { _, _ in
            Task { await loadStats() }
        }
        .onChange(of: minHands) { _, _ in
            Task { await loadStats() }
        }
        .onChange(of: heroPlayerName) { _, _ in
            Task { await loadStats() }
        }
    }

    private func loadHeroes() async {
        do {
            // Find all players that have been marked as hero in any hand
            let heroes: [String] = try await DatabaseManager.shared.reader.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT DISTINCT p.username
                    FROM players p
                    INNER JOIN hand_players hp ON hp.playerId = p.id
                    WHERE hp.isHero = 1
                    ORDER BY p.username
                """)
                return rows.map { $0["username"] as String }
            }
            availableHeroes = heroes
            // Auto-select the first hero if available
            if heroPlayerName.isEmpty, let first = heroes.first {
                heroPlayerName = first
            }
        } catch {
            print("Error loading heroes: \(error)")
        }
    }

    private func loadStats() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let filters = createFilters(for: selectedTimeRange)
            let allStats = try StatsCalculator().getAllPlayerStats(minHands: minHands, filters: filters)
            playerStats = allStats
            if allStats.isEmpty {
                errorMessage = "No players found with \(minHands)+ hands. Try lowering Min Hands."
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
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

// MARK: - Hero Summary Card

struct HeroSummaryCard: View {
    let stats: PlayerStats

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(stats.playerName)
                    .font(.title2)
                    .fontWeight(.bold)

                PlayerTypeBadge(type: stats.playerType, fontSize: 11)

                Spacer()

                Text("\(stats.handsPlayed) hands")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("BB/100").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: "%+.2f", stats.bb100))
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(stats.bb100 >= 0 ? .green : .red)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("Total Won").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: "%+.2f", stats.totalWon))
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(stats.totalWon >= 0 ? .green : .red)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("VPIP / PFR").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: "%.0f / %.0f", stats.vpip, stats.pfr))
                        .font(.title3).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("3-Bet").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: "%.1f%%", stats.threeBet))
                        .font(.title3).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("AF").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: "%.1f", stats.aggressionFactor))
                        .font(.title3).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(stats.bb100 >= 0 ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(stats.bb100 >= 0 ? Color.green.opacity(0.2) : Color.red.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Stats Table

struct PlayerStatsTable: View {
    let stats: [PlayerStats]
    let heroName: String

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
                PlayerStatsRow(stat: stat, isHero: stat.playerName == heroName)
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
    let isHero: Bool

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                if isHero {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption2)
                }
                Text(stat.playerName)
                    .fontWeight(isHero ? .bold : .regular)
            }
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
        .background(isHero ? Color.yellow.opacity(0.05) : Color.clear)
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
