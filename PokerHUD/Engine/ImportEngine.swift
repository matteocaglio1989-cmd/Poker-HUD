import Foundation
import GRDB

/// Handles importing hand history files into the database
class ImportEngine {
    private let databaseManager: DatabaseManager
    private let statsCalculator: StatsCalculator
    private let handRepository: HandRepository
    private let playerRepository: PlayerRepository

    init(databaseManager: DatabaseManager = .shared, statsCalculator: StatsCalculator) {
        self.databaseManager = databaseManager
        self.statsCalculator = statsCalculator
        self.handRepository = HandRepository(databaseManager: databaseManager)
        self.playerRepository = PlayerRepository(databaseManager: databaseManager)
    }

    /// Import hand history files
    /// - Parameters:
    ///   - urls: URLs of files to import
    ///   - progressHandler: Optional progress callback (0.0 to 1.0)
    /// - Returns: Import result with stats
    @discardableResult
    func importFiles(_ urls: [URL], progressHandler: ((Double) -> Void)? = nil) async throws -> ImportResult {
        var totalHands = 0
        var totalPlayers = 0
        var errors: [ImportError] = []

        for (index, url) in urls.enumerated() {
            do {
                let result = try await importFile(url)
                totalHands += result.handsImported
                totalPlayers += result.newPlayers

                let progress = Double(index + 1) / Double(urls.count)
                progressHandler?(progress)
            } catch {
                errors.append(ImportError(file: url.lastPathComponent, error: error))
            }
        }

        return ImportResult(
            handsImported: totalHands,
            newPlayers: totalPlayers,
            errors: errors
        )
    }

    /// Import a single hand history file
    /// - Parameter url: URL of file to import
    /// - Returns: Import result for this file
    private func importFile(_ url: URL) async throws -> ImportResult {
        // Read file content
        let content = try String(contentsOf: url, encoding: .utf8)

        // Detect parser
        guard let parser = ParserFactory.parser(for: content) else {
            throw ImportEngineError.unsupportedFormat
        }

        // Find or create site
        let site = try findOrCreateSite(name: parser.siteName)

        // Parse hands
        let parsedHands = try parser.parse(content)

        var handsImported = 0
        var newPlayers = 0

        for parsedHand in parsedHands {
            // Check if hand already exists
            if try handRepository.fetchByHandId(parsedHand.hand.handId, siteId: site.id!) != nil {
                continue // Skip duplicate
            }

            // Calculate stats for players
            let playersWithStats = statsCalculator.calculateHandStats(
                players: parsedHand.players,
                actions: parsedHand.actions
            )

            // Import hand with players and actions
            try await importHand(parsedHand.hand, players: playersWithStats, actions: parsedHand.actions, site: site)

            handsImported += 1
            newPlayers += parsedHand.players.count
        }

        return ImportResult(
            handsImported: handsImported,
            newPlayers: newPlayers,
            errors: []
        )
    }

    /// Import a single hand into the database
    private func importHand(_ handData: HandData, players: [PlayerData], actions: [ActionData], site: Site) async throws {
        // Find or create tournament if applicable
        var tournamentId: Int64? = nil
        if let tournamentIdString = handData.tournamentId {
            let tournament = try findOrCreateTournament(tournamentId: tournamentIdString, siteId: site.id!)
            tournamentId = tournament.id
        }

        // Create hand record
        var hand = Hand(
            id: nil,
            siteId: site.id!,
            handId: handData.handId,
            tournamentId: tournamentId,
            tableName: handData.tableName,
            gameType: handData.gameType,
            limitType: handData.limitType,
            tableSize: handData.tableSize,
            smallBlind: handData.smallBlind,
            bigBlind: handData.bigBlind,
            ante: handData.ante,
            board: handData.board,
            potTotal: handData.potTotal,
            rake: handData.rake,
            playedAt: handData.playedAt,
            rawText: handData.rawText
        )

        // Create player records
        var handPlayers: [HandPlayer] = []
        for playerData in players {
            // Find or create player
            let player = try playerRepository.findOrCreate(username: playerData.username, siteId: site.id!)

            let handPlayer = HandPlayer(
                id: nil,
                handId: 0, // Will be set after hand insert
                playerId: player.id!,
                seat: playerData.seat,
                position: playerData.position,
                holeCards: playerData.holeCards,
                isHero: playerData.isHero,
                startingStack: playerData.startingStack,
                totalBet: playerData.totalBet,
                totalWon: playerData.totalWon,
                netResult: playerData.netResult,
                wentToShowdown: playerData.wentToShowdown,
                wonAtShowdown: playerData.wonAtShowdown,
                vpip: playerData.vpip,
                pfr: playerData.pfr,
                threeBet: playerData.threeBet,
                fourBet: playerData.fourBet,
                coldCall: playerData.coldCall,
                squeeze: playerData.squeeze,
                foldToThreeBet: playerData.foldToThreeBet,
                cbetFlop: playerData.cbetFlop,
                foldToCbetFlop: playerData.foldToCbetFlop,
                checkRaiseFlop: playerData.checkRaiseFlop,
                cbetTurn: playerData.cbetTurn,
                foldToCbetTurn: playerData.foldToCbetTurn,
                cbetRiver: playerData.cbetRiver,
                foldToCbetRiver: playerData.foldToCbetRiver,
                aggressionFactor: playerData.aggressionFactor,
                allIn: playerData.allIn
            )
            handPlayers.append(handPlayer)
        }

        // Create action records
        var actionRecords: [Action] = []
        for actionData in actions {
            // Find player ID
            if let playerData = players.first(where: { $0.username == actionData.username }),
               let player = try? playerRepository.fetchByUsername(playerData.username, siteId: site.id!) {
                let action = Action(
                    id: nil,
                    handId: 0, // Will be set after hand insert
                    playerId: player.id!,
                    street: actionData.street,
                    actionOrder: actionData.actionOrder,
                    actionType: actionData.actionType,
                    amount: actionData.amount,
                    potBefore: actionData.potBefore,
                    potAfter: actionData.potAfter
                )
                actionRecords.append(action)
            }
        }

        // Insert into database
        try handRepository.insertHandWithPlayers(&hand, players: &handPlayers, actions: actionRecords)
    }

    /// Find or create a site record
    private func findOrCreateSite(name: String) throws -> Site {
        try databaseManager.writer.write { db in
            if let existing = try Site.filter(Site.Columns.name == name).fetchOne(db) {
                return existing
            }

            var site = Site(id: nil, name: name, handHistoryPath: nil, autoImport: false)
            try site.insert(db)
            return site
        }
    }

    /// Find or create a tournament record
    private func findOrCreateTournament(tournamentId: String, siteId: Int64) throws -> Tournament {
        try databaseManager.writer.write { db in
            if let existing = try Tournament
                .filter(Tournament.Columns.tournamentId == tournamentId &&
                       Tournament.Columns.siteId == siteId)
                .fetchOne(db) {
                return existing
            }

            var tournament = Tournament(
                id: nil,
                siteId: siteId,
                tournamentId: tournamentId,
                name: nil,
                buyIn: nil,
                rake: nil,
                bounty: nil,
                prizePool: nil,
                finishPosition: nil,
                totalPlayers: nil,
                payout: nil,
                startTime: nil,
                endTime: nil,
                gameType: nil
            )
            try tournament.insert(db)
            return tournament
        }
    }
}

// MARK: - Supporting Types

struct ImportResult {
    let handsImported: Int
    let newPlayers: Int
    let errors: [ImportError]

    var isSuccess: Bool {
        errors.isEmpty
    }
}

struct ImportError {
    let file: String
    let error: Error
}

enum ImportEngineError: LocalizedError {
    case unsupportedFormat
    case fileReadError
    case databaseError(Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported hand history format"
        case .fileReadError:
            return "Failed to read file"
        case .databaseError(let error):
            return "Database error: \(error.localizedDescription)"
        }
    }
}
