import Foundation
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var isImporting = false
    @Published var importProgress: Double = 0.0
    @Published var selectedSite: Site?
    @Published var activeTables: [TableInfo] = []
    @Published var currentSession: Session?

    let databaseManager: DatabaseManager
    let importEngine: ImportEngine
    let statsCalculator: StatsCalculator

    init() {
        self.databaseManager = DatabaseManager.shared
        self.statsCalculator = StatsCalculator(databaseManager: databaseManager)
        self.importEngine = ImportEngine(
            databaseManager: databaseManager,
            statsCalculator: statsCalculator
        )
    }

    @discardableResult
    func importHandHistoryFiles(_ urls: [URL]) async throws -> ImportResult {
        await MainActor.run {
            isImporting = true
            importProgress = 0.0
        }

        defer {
            Task { @MainActor in
                isImporting = false
                importProgress = 0.0
            }
        }

        return try await importEngine.importFiles(urls) { progress in
            Task { @MainActor in
                self.importProgress = progress
            }
        }
    }
}

struct TableInfo: Identifiable {
    let id = UUID()
    let tableName: String
    let site: String
    let stakes: String
    let playerCount: Int
}
