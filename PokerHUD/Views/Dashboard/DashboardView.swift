import SwiftUI
import GRDB

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var isImporting = false
    @State private var totalHands = 0
    @State private var totalPlayers = 0
    @State private var recentHands: [Hand] = []
    @State private var showImportAlert = false
    @State private var importAlertTitle = ""
    @State private var importAlertMessage = ""
    @State private var activeSession: SessionSummary? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Dashboard")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Import and analyze your poker hands")
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { isImporting = true }) {
                        Label("Import Hands", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()

                // Stats Cards
                HStack(spacing: 16) {
                    StatCard(title: "Total Hands", value: "\(totalHands)", icon: "suit.club.fill", color: .blue)
                    StatCard(title: "Players Tracked", value: "\(totalPlayers)", icon: "person.3.fill", color: .green)
                    StatCard(title: "Active Tables", value: "\(appState.managedTables.filter { $0.isHUDVisible }.count)", icon: "square.grid.2x2.fill", color: .orange)
                }
                .padding(.horizontal)

                // Import Progress
                if appState.isImporting {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Importing hands...")
                            .font(.headline)
                        ProgressView(value: appState.importProgress)
                        Text("\(Int(appState.importProgress * 100))% complete")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }

                // Auto-Import Activity
                AutoImportActivityView()
                    .environmentObject(appState)
                    .padding(.horizontal)

                // Active Session Report
                if let session = activeSession {
                    ActiveSessionView(session: session)
                        .padding(.horizontal)
                }

                // Recent Hands (last 3)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Hands")
                        .font(.headline)
                        .padding(.horizontal)

                    if recentHands.isEmpty {
                        EmptyStateView()
                    } else {
                        ForEach(recentHands) { hand in
                            RecentHandRow(hand: hand)
                        }
                    }
                }
                .padding(.bottom)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.text, .plainText],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .alert(importAlertTitle, isPresented: $showImportAlert) {
            Button("OK") {}
        } message: {
            Text(importAlertMessage)
        }
        .task {
            await loadData()
        }
        .onChange(of: appState.lastAutoImportTime) { _, _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        do {
            let handRepo = HandRepository()
            let playerRepo = PlayerRepository()

            totalHands = try handRepo.count()
            totalPlayers = try playerRepo.count()
            recentHands = try handRepo.fetchRecent(limit: 3)
            activeSession = try computeActiveSession()
        } catch {
            print("Error loading dashboard data: \(error)")
        }
    }

    // MARK: - Session Detection

    /// Detect the current/latest session by finding the hero's recent hands
    /// A session = consecutive hands where gaps between hands are < 30 minutes
    private func computeActiveSession() throws -> SessionSummary? {
        let db = DatabaseManager.shared

        // Find the hero player (isHero = true) and their recent hands
        let rows: [Row] = try db.reader.read { database in
            try Row.fetchAll(database, sql: """
                SELECT h.id, h.playedAt, h.tableName, h.bigBlind, h.stakes,
                       hp.netResult, hp.vpip, hp.pfr, hp.wentToShowdown, hp.wonAtShowdown, hp.isHero
                FROM hand_players hp
                INNER JOIN hands h ON h.id = hp.handId
                WHERE hp.isHero = 1
                ORDER BY h.playedAt DESC
                LIMIT 500
            """)
        }

        guard !rows.isEmpty else { return nil }

        // Group into sessions: gap > 30 min = new session
        let sessionGap: TimeInterval = 30 * 60

        var sessionHands: [(date: Date, netResult: Double, bigBlind: Double, vpip: Bool, pfr: Bool, wtsd: Bool, wsd: Bool)] = []
        var tableName: String? = nil
        var stakes: String? = nil

        for (index, row) in rows.enumerated() {
            let playedAt: Date = row["playedAt"]
            let netResult: Double = row["netResult"]
            let bigBlind: Double = row["bigBlind"]
            let vpip: Bool = row["vpip"]
            let pfr: Bool = row["pfr"]
            let wtsd: Bool = row["wentToShowdown"]
            let wsd: Bool = row["wonAtShowdown"]

            if index == 0 {
                tableName = row["tableName"] as? String
                stakes = row["stakes"] as? String
                sessionHands.append((playedAt, netResult, bigBlind, vpip, pfr, wtsd, wsd))
                continue
            }

            let prevDate = sessionHands.last!.date
            if prevDate.timeIntervalSince(playedAt) > sessionGap {
                break // Previous hand was > 30min ago = end of session
            }

            sessionHands.append((playedAt, netResult, bigBlind, vpip, pfr, wtsd, wsd))
        }

        guard !sessionHands.isEmpty else { return nil }

        // Compute session stats
        let handsPlayed = sessionHands.count
        let totalNet = sessionHands.reduce(0.0) { $0 + $1.netResult }
        let avgBB = sessionHands.map { $0.bigBlind }.reduce(0.0, +) / Double(handsPlayed)
        let bb100 = avgBB > 0 ? (totalNet / avgBB) / Double(handsPlayed) * 100 : 0
        let vpipCount = sessionHands.filter { $0.vpip }.count
        let pfrCount = sessionHands.filter { $0.pfr }.count
        let wtsdCount = sessionHands.filter { $0.wtsd }.count
        let wsdCount = sessionHands.filter { $0.wsd }.count
        let vpipPct = Double(vpipCount) / Double(handsPlayed) * 100
        let pfrPct = Double(pfrCount) / Double(handsPlayed) * 100
        let wtsdPct = handsPlayed > 0 ? Double(wtsdCount) / Double(handsPlayed) * 100 : 0
        let wsdPct = wtsdCount > 0 ? Double(wsdCount) / Double(wtsdCount) * 100 : 0

        let startTime = sessionHands.last!.date   // oldest hand
        let endTime = sessionHands.first!.date     // newest hand
        let duration = endTime.timeIntervalSince(startTime)

        // Is session still active? (last hand < 30 min ago)
        let isActive = Date().timeIntervalSince(endTime) < sessionGap

        return SessionSummary(
            tableName: tableName ?? "Unknown",
            stakes: stakes ?? "?",
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            isActive: isActive,
            handsPlayed: handsPlayed,
            netResult: totalNet,
            bb100: bb100,
            vpip: vpipPct,
            pfr: pfrPct,
            wtsd: wtsdPct,
            wsd: wsdPct,
            bigBlind: avgBB
        )
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        Task {
            switch result {
            case .success(let urls):
                do {
                    let importResult = try await appState.importHandHistoryFiles(urls)
                    await loadData()
                    importAlertTitle = "Import Complete"
                    importAlertMessage = "\(importResult.handsImported) hands imported, \(importResult.newPlayers) players found."
                    if !importResult.errors.isEmpty {
                        importAlertMessage += "\n\(importResult.errors.count) error(s) occurred."
                    }
                    showImportAlert = true
                } catch {
                    importAlertTitle = "Import Failed"
                    importAlertMessage = error.localizedDescription
                    showImportAlert = true
                }
            case .failure(let error):
                importAlertTitle = "File Error"
                importAlertMessage = error.localizedDescription
                showImportAlert = true
            }
        }
    }
}

// MARK: - Session Summary Model

struct SessionSummary {
    let tableName: String
    let stakes: String
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let isActive: Bool
    let handsPlayed: Int
    let netResult: Double
    let bb100: Double
    let vpip: Double
    let pfr: Double
    let wtsd: Double
    let wsd: Double
    let bigBlind: Double

    var durationFormatted: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var handsPerHour: Int {
        let hours = duration / 3600
        guard hours > 0 else { return handsPlayed }
        return Int(Double(handsPlayed) / hours)
    }

    var netResultInBB: Double {
        guard bigBlind > 0 else { return 0 }
        return netResult / bigBlind
    }
}

// MARK: - Active Session View

struct ActiveSessionView: View {
    let session: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.isActive ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(session.isActive ? "Active Session" : "Last Session")
                        .font(.headline)
                }

                Spacer()

                Text(session.tableName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(session.stakes)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }

            Divider()

            // Key metrics row
            HStack(spacing: 0) {
                SessionMetric(
                    label: "Profit/Loss",
                    value: String(format: "%+.2f", session.netResult),
                    subvalue: String(format: "%+.1f BB", session.netResultInBB),
                    color: session.netResult >= 0 ? .green : .red
                )
                SessionMetric(
                    label: "Hands",
                    value: "\(session.handsPlayed)",
                    subvalue: "\(session.handsPerHour)/hr"
                )
                SessionMetric(
                    label: "Duration",
                    value: session.durationFormatted,
                    subvalue: formatTimeRange(session.startTime, session.endTime)
                )
                SessionMetric(
                    label: "BB/100",
                    value: String(format: "%+.1f", session.bb100),
                    color: session.bb100 >= 0 ? .green : .red
                )
            }

            Divider()

            // Session stats row
            HStack(spacing: 20) {
                HStack(spacing: 4) {
                    Text("VPIP").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: "%.0f%%", session.vpip)).font(.caption).fontWeight(.medium)
                }
                HStack(spacing: 4) {
                    Text("PFR").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: "%.0f%%", session.pfr)).font(.caption).fontWeight(.medium)
                }
                HStack(spacing: 4) {
                    Text("WTSD").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: "%.0f%%", session.wtsd)).font(.caption).fontWeight(.medium)
                }
                HStack(spacing: 4) {
                    Text("W$SD").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: "%.0f%%", session.wsd)).font(.caption).fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(session.netResult >= 0 ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(session.netResult >= 0 ? Color.green.opacity(0.2) : Color.red.opacity(0.2), lineWidth: 1)
        )
    }

    private func formatTimeRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}

struct SessionMetric: View {
    let label: String
    let value: String
    var subvalue: String? = nil
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(color)
            if let sub = subvalue {
                Text(sub)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Reusable Components

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

struct RecentHandRow: View {
    let hand: Hand

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(hand.tableName ?? "Unknown Table")
                    .fontWeight(.medium)
                Text("\(hand.gameType) \(hand.limitType) - \(hand.stakes)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(hand.playedAt, style: .time)
                    .font(.caption)
                Text(hand.playedAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Auto-Import Activity

struct AutoImportActivityView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(appState.isFileWatcherActive ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text("Auto-Import")
                    .font(.headline)

                if appState.isFileWatcherActive {
                    Text("Active")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                } else {
                    Text("Inactive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }

                Spacer()

                if let path = appState.handHistoryPath {
                    Text(path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            if appState.autoImportLog.isEmpty {
                if appState.isFileWatcherActive {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Watching for new hands...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("Configure a hand history path in Settings or HUD tab to enable auto-import")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
            } else {
                ForEach(appState.autoImportLog.prefix(3)) { event in
                    HStack(spacing: 8) {
                        Image(systemName: event.success ? (event.handsImported > 0 ? "checkmark.circle.fill" : "arrow.clockwise.circle.fill") : "xmark.circle.fill")
                            .foregroundColor(event.success ? (event.handsImported > 0 ? .green : .blue) : .red)
                            .font(.caption)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.filename)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if event.success {
                                if event.handsImported > 0 {
                                    Text("+\(event.handsImported) new hands, \(event.playersAffected) players")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                } else if event.handsSkipped > 0 {
                                    Text("Scanned \(event.handsSkipped) hands (all already imported)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("No hands found in file")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text(event.errorMessage ?? "Import failed")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }

                        Spacer()

                        Text(event.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No hands imported yet")
                .font(.headline)
            Text("Import your first hand history file to get started")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}
