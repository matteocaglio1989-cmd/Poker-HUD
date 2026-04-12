import Foundation
import GRDB

/// Handles importing hand history files into the database
class ImportEngine {
    private let databaseManager: DatabaseManager
    private let statsCalculator: StatsCalculator
    private let handRepository: HandRepository
    private let playerRepository: PlayerRepository
    /// Optional publisher that is notified after every successful
    /// `importFileForHUD` call. Injected by `AppState` so the HUD layer
    /// can refresh without the import engine knowing about it directly.
    private let importPublisher: HandImportPublisher?

    init(
        databaseManager: DatabaseManager = .shared,
        statsCalculator: StatsCalculator,
        importPublisher: HandImportPublisher? = nil
    ) {
        self.databaseManager = databaseManager
        self.statsCalculator = statsCalculator
        self.handRepository = HandRepository(databaseManager: databaseManager)
        self.playerRepository = PlayerRepository(databaseManager: databaseManager)
        self.importPublisher = importPublisher
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
        guard let siteId = site.id else {
            throw ImportEngineError.missingPersistedID("Site")
        }

        // Parse hands
        var parsedHands = try parser.parse(content)

        // Detect money type from the source filename:
        //   "Play Money" in name → PLAY_MONEY
        //   tournamentId present → TOURNAMENT
        //   otherwise → CASH (parser default)
        let isPlayMoneyFile = url.lastPathComponent
            .localizedCaseInsensitiveContains("Play Money")
        for i in parsedHands.indices {
            if isPlayMoneyFile {
                parsedHands[i].hand.moneyType = "PLAY_MONEY"
            } else if parsedHands[i].hand.tournamentId != nil {
                parsedHands[i].hand.moneyType = "TOURNAMENT"
            }
        }

        var handsImported = 0
        var newPlayers = 0

        for parsedHand in parsedHands {
            // Check if hand already exists
            if try handRepository.fetchByHandId(parsedHand.hand.handId, siteId: siteId) != nil {
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
        guard let siteId = site.id else {
            throw ImportEngineError.missingPersistedID("Site")
        }

        // Find or create tournament if applicable
        var tournamentId: Int64? = nil
        if let tournamentIdString = handData.tournamentId {
            let tournament = try findOrCreateTournament(tournamentId: tournamentIdString, siteId: siteId)
            tournamentId = tournament.id
        }

        // Create hand record
        var hand = Hand(
            id: nil,
            siteId: siteId,
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
            rawText: handData.rawText,
            moneyType: handData.moneyType
        )

        // Create player records
        var handPlayers: [HandPlayer] = []
        for playerData in players {
            // Find or create player
            let player = try playerRepository.findOrCreate(username: playerData.username, siteId: siteId)
            guard let playerId = player.id else {
                throw ImportEngineError.missingPersistedID("Player \(playerData.username)")
            }

            let handPlayer = HandPlayer(
                id: nil,
                handId: 0, // Will be set after hand insert
                playerId: playerId,
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
               let player = try? playerRepository.fetchByUsername(playerData.username, siteId: siteId),
               let playerId = player.id {
                let action = Action(
                    id: nil,
                    handId: 0, // Will be set after hand insert
                    playerId: playerId,
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
            site.id = db.lastInsertedRowID
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
            tournament.id = db.lastInsertedRowID
            return tournament
        }
    }

    // MARK: - HUD Import

    /// Import a single file and return enriched results for HUD refresh
    func importFileForHUD(_ url: URL) async throws -> HUDImportResult {
        let content = try String(contentsOf: url, encoding: .utf8)

        guard let parser = ParserFactory.parser(for: content) else {
            throw ImportEngineError.unsupportedFormat
        }

        let site = try findOrCreateSite(name: parser.siteName)
        guard let siteId = site.id else {
            throw ImportEngineError.missingPersistedID("Site")
        }
        var parsedHands = try parser.parse(content)

        // Detect money type (same logic as importFile)
        let isPlayMoneyFile = url.lastPathComponent
            .localizedCaseInsensitiveContains("Play Money")
        for i in parsedHands.indices {
            if isPlayMoneyFile {
                parsedHands[i].hand.moneyType = "PLAY_MONEY"
            } else if parsedHands[i].hand.tournamentId != nil {
                parsedHands[i].hand.moneyType = "TOURNAMENT"
            }
        }

        var handsImported = 0
        var affectedTableNames = Set<String>()
        var affectedPlayerNames = Set<String>()
        var errors: [ImportError] = []
        // Track the latest seat layout per table (last hand wins)
        var tableSeats: [String: [TableSeatInfo]] = [:]

        for parsedHand in parsedHands {
            // Always update seat layout from every hand (even duplicates)
            // so we always have the latest player positions
            let tableName = parsedHand.hand.tableName
            let stakes = "\(parsedHand.hand.smallBlind)/\(parsedHand.hand.bigBlind)"
            tableSeats[tableName] = parsedHand.players.map { player in
                TableSeatInfo(
                    seatNumber: player.seat,
                    playerName: player.username,
                    isHero: player.isHero,
                    tableSize: parsedHand.hand.tableSize,
                    stakes: stakes
                )
            }

            do {
                if try handRepository.fetchByHandId(parsedHand.hand.handId, siteId: siteId) != nil {
                    continue
                }

                let playersWithStats = statsCalculator.calculateHandStats(
                    players: parsedHand.players,
                    actions: parsedHand.actions
                )

                try await importHand(parsedHand.hand, players: playersWithStats, actions: parsedHand.actions, site: site)

                handsImported += 1
                affectedTableNames.insert(tableName)
                for player in parsedHand.players {
                    affectedPlayerNames.insert(player.username)
                }
            } catch {
                errors.append(ImportError(file: url.lastPathComponent, error: error))
            }
        }

        let result = HUDImportResult(
            handsImported: handsImported,
            handsParsed: parsedHands.count,
            affectedTableNames: affectedTableNames,
            affectedPlayerNames: affectedPlayerNames,
            errors: errors,
            tableSeats: tableSeats
        )
        // Notify any subscribers (the HUD layer). `HandImportPublisher`
        // internally no-ops when `handsImported == 0`, so this is cheap
        // for files that turn out to be all duplicates.
        importPublisher?.publish(result)
        return result
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
    /// Thrown when a GRDB-inserted row is missing its rowid after insert —
    /// should be impossible given how GRDB's `didInsert` populates the `id`,
    /// but guarding lets the importer fail gracefully instead of crashing
    /// the whole app on a schema regression.
    case missingPersistedID(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported hand history format"
        case .fileReadError:
            return "Failed to read file"
        case .databaseError(let error):
            return "Database error: \(error.localizedDescription)"
        case .missingPersistedID(let entity):
            return "Database did not return a row id for \(entity) after insert"
        }
    }
}
