import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var isImporting = false
    @State private var totalHands = 0
    @State private var totalPlayers = 0
    @State private var recentHands: [Hand] = []
    @State private var showImportAlert = false
    @State private var importAlertTitle = ""
    @State private var importAlertMessage = ""

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
                    StatCard(
                        title: "Total Hands",
                        value: "\(totalHands)",
                        icon: "suit.club.fill",
                        color: .blue
                    )

                    StatCard(
                        title: "Players Tracked",
                        value: "\(totalPlayers)",
                        icon: "person.3.fill",
                        color: .green
                    )

                    StatCard(
                        title: "Active Tables",
                        value: "\(appState.activeTables.count)",
                        icon: "square.grid.2x2.fill",
                        color: .orange
                    )
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

                // Recent Hands
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
    }

    private func loadData() async {
        do {
            let handRepo = HandRepository()
            let playerRepo = PlayerRepository()

            totalHands = try handRepo.count()
            totalPlayers = try playerRepo.count()
            recentHands = try handRepo.fetchRecent(limit: 20)
        } catch {
            print("Error loading dashboard data: \(error)")
        }
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
