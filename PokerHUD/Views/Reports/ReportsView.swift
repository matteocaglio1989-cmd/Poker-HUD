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

    // Phase 3 PR1 filter state
    @State private var selectedPosition: PositionFilter = .all
    @State private var selectedGameType: GameTypeFilter = .all
    @State private var selectedStakes: StakesFilter = .all

    // Sortable table state. nil = preserve repository order (handsPlayed DESC).
    @State private var sortColumn: SortColumn? = nil
    @State private var sortAscending: Bool = false

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

                        // Phase 3 PR1: position / game type / stakes filters
                        HStack {
                            Picker("Position", selection: $selectedPosition) {
                                ForEach(PositionFilter.allCases) { p in
                                    Text(p.title).tag(p)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 140)

                            Picker("Game", selection: $selectedGameType) {
                                ForEach(GameTypeFilter.allCases) { g in
                                    Text(g.title).tag(g)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 140)

                            Picker("Stakes", selection: $selectedStakes) {
                                ForEach(StakesFilter.allCases) { s in
                                    Text(s.title).tag(s)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 140)
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

                        PlayerStatsTable(
                            stats: sortedStats,
                            heroName: heroPlayerName,
                            sortColumn: $sortColumn,
                            sortAscending: $sortAscending
                        )
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
        .onChange(of: selectedPosition) { _, _ in
            Task { await loadStats() }
        }
        .onChange(of: selectedGameType) { _, _ in
            Task { await loadStats() }
        }
        .onChange(of: selectedStakes) { _, _ in
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
                errorMessage = "No players found with \(minHands)+ hands matching the current filters. Try widening the filter or lowering Min Hands."
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            print("Error loading stats: \(error)")
        }
    }

    /// Phase 3 PR1: client-side sort applied on top of the repository's
    /// default ordering (handsPlayed DESC). When `sortColumn == nil` we
    /// preserve the SQL order so the table looks identical to before the
    /// sort feature shipped.
    private var sortedStats: [PlayerStats] {
        guard let column = sortColumn else { return playerStats }
        let asc = sortAscending
        return playerStats.sorted { lhs, rhs in
            let cmp: Bool
            switch column {
            case .player:       cmp = lhs.playerName < rhs.playerName
            case .hands:        cmp = lhs.handsPlayed < rhs.handsPlayed
            case .vpip:         cmp = lhs.vpip < rhs.vpip
            case .pfr:          cmp = lhs.pfr < rhs.pfr
            case .threeBet:     cmp = lhs.threeBet < rhs.threeBet
            case .af:           cmp = lhs.aggressionFactor < rhs.aggressionFactor
            case .wtsd:         cmp = lhs.wtsd < rhs.wtsd
            case .wsd:          cmp = lhs.wsd < rhs.wsd
            case .bb100:        cmp = lhs.bb100 < rhs.bb100
            case .cbetFlop:     cmp = lhs.cbetFlop < rhs.cbetFlop
            case .foldCbetFlop: cmp = lhs.foldToCbetFlop < rhs.foldToCbetFlop
            case .squeeze:      cmp = lhs.squeeze < rhs.squeeze
            case .fourBet:      cmp = lhs.fourBet < rhs.fourBet
            case .foldThreeBet: cmp = lhs.foldToThreeBet < rhs.foldToThreeBet
            }
            return asc ? cmp : !cmp
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

        // Phase 3 PR1: thread the new UI filters into the SQL.
        if let pos = selectedPosition.sqlValue {
            filters.position = pos
        }
        if let game = selectedGameType.sqlValue {
            filters.gameType = game
        }
        if let stakes = selectedStakes.bigBlindRange {
            filters.minStakes = stakes.lowerBound
            filters.maxStakes = stakes.upperBound
        }
        if !heroPlayerName.isEmpty {
            filters.heroPlayerName = heroPlayerName
        }

        return filters
    }
}

// MARK: - Phase 3 PR1 filter enums

enum PositionFilter: String, CaseIterable, Identifiable, Hashable {
    case all, utg, mp, co, btn, sb, bb
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All Positions"
        case .utg: return "UTG"
        case .mp:  return "MP"
        case .co:  return "CO"
        case .btn: return "BTN"
        case .sb:  return "SB"
        case .bb:  return "BB"
        }
    }
    /// Value passed to the SQL `hp.position = ?` clause, or nil for "no filter".
    var sqlValue: String? {
        switch self {
        case .all: return nil
        default:   return rawValue.uppercased()
        }
    }
}

enum GameTypeFilter: String, CaseIterable, Identifiable, Hashable {
    case all, holdem, omaha
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all:    return "All Games"
        case .holdem: return "Hold'em"
        case .omaha:  return "Omaha"
        }
    }
    /// Value passed to the SQL `h.gameType = ?` clause. The PokerStars
    /// parser stores game types like "Hold'em" / "Omaha" verbatim, which
    /// is what we need to match.
    var sqlValue: String? {
        switch self {
        case .all:    return nil
        case .holdem: return "Hold'em"
        case .omaha:  return "Omaha"
        }
    }
}

enum StakesFilter: String, CaseIterable, Identifiable, Hashable {
    case all, micro, low, mid, high
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all:   return "All Stakes"
        case .micro: return "Micro (≤ €0.10)"
        case .low:   return "Low (€0.10–€1)"
        case .mid:   return "Mid (€1–€5)"
        case .high:  return "High (≥ €5)"
        }
    }
    /// Bounds expressed in big blinds (the table column we filter on).
    var bigBlindRange: ClosedRange<Double>? {
        switch self {
        case .all:   return nil
        case .micro: return 0.001...0.10
        case .low:   return 0.10...1.00
        case .mid:   return 1.00...5.00
        case .high:  return 5.00...10000.00
        }
    }
}

// MARK: - Phase 3 PR1 sortable column enum

enum SortColumn: String, Hashable {
    case player, hands, vpip, pfr, threeBet, af, wtsd, wsd, bb100
    case cbetFlop, foldCbetFlop, squeeze, fourBet, foldThreeBet
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
    @Binding var sortColumn: SortColumn?
    @Binding var sortAscending: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                // Header — every column tappable to sort. Click toggles
                // ascending/descending; clicking a different column resets
                // to descending (the most useful default for poker stats).
                HStack(spacing: 0) {
                    headerCell("Player", column: .player, width: 150, alignment: .leading)
                    headerCell("Hands", column: .hands, width: 60)
                    headerCell("VPIP", column: .vpip, width: 60)
                    headerCell("PFR", column: .pfr, width: 60)
                    headerCell("3Bet", column: .threeBet, width: 60)
                    headerCell("4Bet", column: .fourBet, width: 60)
                    headerCell("F3B", column: .foldThreeBet, width: 60)
                    headerCell("Sqz", column: .squeeze, width: 60)
                    headerCell("CBetF", column: .cbetFlop, width: 65)
                    headerCell("FCBF", column: .foldCbetFlop, width: 65)
                    headerCell("AF", column: .af, width: 60)
                    headerCell("WTSD", column: .wtsd, width: 60)
                    headerCell("W$SD", column: .wsd, width: 60)
                    headerCell("BB/100", column: .bb100, width: 80)
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

    /// One sortable column header. Tap toggles direction; tapping a
    /// different column resets to descending (the default for stats —
    /// "best players first" / "highest VPIP first" etc.). Renders an
    /// arrow indicator next to the active column.
    @ViewBuilder
    private func headerCell(
        _ label: String,
        column: SortColumn,
        width: CGFloat,
        alignment: Alignment = .trailing
    ) -> some View {
        let isActive = sortColumn == column
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = false
            }
        } label: {
            HStack(spacing: 2) {
                if alignment == .leading {
                    Text(label)
                    if isActive {
                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                            .font(.system(size: 8))
                    }
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    Text(label)
                    if isActive {
                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                            .font(.system(size: 8))
                    }
                }
            }
            .frame(width: width, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PlayerStatsRow: View {
    let stat: PlayerStats
    let isHero: Bool

    var body: some View {
        HStack(spacing: 0) {
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
            // Phase 3 PR1: 5 new situational columns surfacing data that
            // was already computed at import time but never rendered.
            Text(String(format: "%.1f", stat.fourBet))
                .frame(width: 60, alignment: .trailing)
            Text(String(format: "%.1f", stat.foldToThreeBet))
                .frame(width: 60, alignment: .trailing)
            Text(String(format: "%.1f", stat.squeeze))
                .frame(width: 60, alignment: .trailing)
            Text(String(format: "%.1f", stat.cbetFlop))
                .frame(width: 65, alignment: .trailing)
            Text(String(format: "%.1f", stat.foldToCbetFlop))
                .frame(width: 65, alignment: .trailing)
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
