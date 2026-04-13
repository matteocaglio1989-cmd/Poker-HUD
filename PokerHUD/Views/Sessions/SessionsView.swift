import SwiftUI
import GRDB

/// Phase 3 PR3: top-level Sessions tab. Lists every historical session
/// for the hero (newest first). Click a row to drill into a session
/// detail view with the cumulative profit chart.
///
/// Session detection is delegated to `SessionDetector` (Engine layer),
/// which uses the same 30-minute-gap rule the Dashboard's "Active
/// Session" card has been using all along — just exposed for the entire
/// hand history instead of only the most recent run.
struct SessionsView: View {
    @State private var sessions: [PlayedSession] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedHero: String = ""
    @State private var availableHeroes: [String] = []
    @State private var selectedSession: PlayedSession?
    @State private var moneyFilter: MoneyTypeFilter = .all

    private let detector = SessionDetector()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
                .padding(.horizontal)
                .padding(.top)

            if isLoading {
                ProgressView("Loading sessions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                errorState(error)
            } else if sessions.isEmpty {
                emptyState
            } else {
                sessionsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await loadHeroes()
            await load()
        }
        .onChange(of: selectedHero) { _, _ in
            Task { await load() }
        }
        .onChange(of: moneyFilter) { _, _ in
            Task { await load() }
        }
        .sheet(item: $selectedSession) { session in
            SessionDetailView(session: session, heroPlayerName: selectedHero)
                .frame(minWidth: 720, minHeight: 560)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text("Sessions")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Every historical session detected from your hand history")
                    .foregroundColor(.secondary)
            }
            Spacer()
            Picker("Game", selection: $moneyFilter) {
                ForEach(MoneyTypeFilter.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            if !availableHeroes.isEmpty {
                Picker("Hero", selection: $selectedHero) {
                    ForEach(availableHeroes, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
            }
        }
    }

    private var sessionsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(sessions) { session in
                    SessionRow(session: session)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Hydrate per-hand points before presenting.
                            let detailed = (try? detector.detail(for: session, heroPlayerName: selectedHero)) ?? session
                            selectedSession = detailed
                        }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(selectedHero.isEmpty
                 ? "Pick a hero to see sessions"
                 : "No sessions found for \(selectedHero)")
                .font(.headline)
            Text(selectedHero.isEmpty
                 ? "Sessions need a single hero to group hands by."
                 : "Import some hand histories where this hero played, then come back.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("Couldn't load sessions")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    private func loadHeroes() async {
        do {
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
            if selectedHero.isEmpty, let first = heroes.first {
                selectedHero = first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load() async {
        guard !selectedHero.isEmpty else {
            sessions = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            sessions = try detector.allSessions(heroPlayerName: selectedHero, moneyType: moneyFilter.dbValue)
        } catch {
            errorMessage = error.localizedDescription
            sessions = []
        }
    }
}

// MARK: - Row

private struct SessionRow: View {
    let session: PlayedSession

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Date column
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startTime, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(session.startTime, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 100, alignment: .leading)

            // Table + stakes + active dot
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if session.isActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                    Text(session.tableName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                Text("\(session.stakes) — \(session.handsPlayed) hands · \(session.durationFormatted)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // BB/100
            VStack(alignment: .trailing, spacing: 2) {
                Text("BB/100").font(.caption2).foregroundColor(.secondary)
                Text(String(format: "%+.1f", session.bb100))
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(session.bb100 >= 0 ? .green : .red)
            }
            .frame(width: 80)

            // Net result
            VStack(alignment: .trailing, spacing: 2) {
                Text("Net").font(.caption2).foregroundColor(.secondary)
                Text(String(format: "%+.2f", session.netResult))
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(session.netResult >= 0 ? .green : .red)
            }
            .frame(width: 90)

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}
