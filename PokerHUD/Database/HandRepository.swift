import Foundation
import GRDB

class HandRepository {
    private let dbManager: DatabaseManager

    init(databaseManager: DatabaseManager = .shared) {
        self.dbManager = databaseManager
    }

    // MARK: - Create

    func insert(_ hand: inout Hand) throws {
        try dbManager.writer.write { db in
            try hand.insert(db)
        }
    }

    func insertHandWithPlayers(_ hand: inout Hand, players: inout [HandPlayer], actions: [Action]) throws {
        try dbManager.writer.write { db in
            try hand.insert(db)
            hand.id = db.lastInsertedRowID

            for i in 0..<players.count {
                var player = players[i]
                player.handId = hand.id!
                try player.insert(db)
                players[i] = player
            }

            for var action in actions {
                action.handId = hand.id!
                try action.insert(db)
            }
        }
    }

    // MARK: - Read

    func fetchAll() throws -> [Hand] {
        try dbManager.reader.read { db in
            try Hand.fetchAll(db)
        }
    }

    func fetchById(_ id: Int64) throws -> Hand? {
        try dbManager.reader.read { db in
            try Hand.fetchOne(db, key: id)
        }
    }

    func fetchByHandId(_ handId: String, siteId: Int64) throws -> Hand? {
        try dbManager.reader.read { db in
            try Hand
                .filter(Hand.Columns.handId == handId && Hand.Columns.siteId == siteId)
                .fetchOne(db)
        }
    }

    func fetchRecent(limit: Int = 100) throws -> [Hand] {
        try dbManager.reader.read { db in
            try Hand
                .order(Hand.Columns.playedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchForPlayer(_ playerId: Int64, limit: Int = 100) throws -> [Hand] {
        try dbManager.reader.read { db in
            let handPlayerAlias = TableAlias()
            return try Hand
                .joining(required: Hand.handPlayers.aliased(handPlayerAlias)
                    .filter(HandPlayer.Columns.playerId == playerId))
                .order(Hand.Columns.playedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchInDateRange(from: Date, to: Date) throws -> [Hand] {
        try dbManager.reader.read { db in
            try Hand
                .filter(Hand.Columns.playedAt >= from && Hand.Columns.playedAt <= to)
                .order(Hand.Columns.playedAt.desc)
                .fetchAll(db)
        }
    }

    func fetchHandPlayers(forHandId handId: Int64) throws -> [HandPlayer] {
        try dbManager.reader.read { db in
            try HandPlayer
                .filter(HandPlayer.Columns.handId == handId)
                .order(HandPlayer.Columns.seat)
                .fetchAll(db)
        }
    }

    func fetchActions(forHandId handId: Int64) throws -> [Action] {
        try dbManager.reader.read { db in
            try Action
                .filter(Action.Columns.handId == handId)
                .order(Action.Columns.actionOrder)
                .fetchAll(db)
        }
    }

    /// Phase 4 PR1: one-shot fetch that hydrates everything `HandDetailView`
    /// needs. Composes the existing `fetchById` / `fetchHandPlayers` /
    /// `fetchActions` calls plus a bulk player lookup so the detail sheet
    /// can present synchronously after a single repository call.
    func fetchHandWithPlayersAndActions(
        handId: Int64,
        playerRepository: PlayerRepository = PlayerRepository()
    ) throws -> HandDetailBundle? {
        guard let hand = try fetchById(handId) else { return nil }
        let handPlayers = try fetchHandPlayers(forHandId: handId)
        let actions = try fetchActions(forHandId: handId)
        let playerIds = Array(Set(handPlayers.map { $0.playerId }))
        let players = try playerRepository.fetchByIds(playerIds)
        return HandDetailBundle(
            hand: hand,
            handPlayers: handPlayers,
            actions: actions,
            players: players
        )
    }

    // MARK: - Update

    func update(_ hand: Hand) throws {
        try dbManager.writer.write { db in
            try hand.update(db)
        }
    }

    // MARK: - Delete

    func delete(_ hand: Hand) throws {
        try dbManager.writer.write { db in
            // Discard the Bool "did delete" flag — callers don't need it,
            // and letting it bubble out of `write` makes the generic return
            // non-Void and triggers a "result unused" warning at the call site.
            _ = try hand.delete(db)
        }
    }

    func deleteAll() throws {
        try dbManager.writer.write { db in
            // Same reason as above — `deleteAll` returns the deleted-row count
            // which we don't use here.
            _ = try Hand.deleteAll(db)
        }
    }

    // MARK: - Statistics

    func count() throws -> Int {
        try dbManager.reader.read { db in
            try Hand.fetchCount(db)
        }
    }

    func countForPlayer(_ playerId: Int64) throws -> Int {
        try dbManager.reader.read { db in
            try HandPlayer
                .filter(HandPlayer.Columns.playerId == playerId)
                .fetchCount(db)
        }
    }
}

/// Phase 4 PR1: bundle returned by `HandRepository.fetchHandWithPlayersAndActions`.
/// Carries everything `HandDetailView` (and the future Phase 4 PR2 visual
/// replayer engine) needs to render a single hand: the hand row itself, the
/// per-seat `HandPlayer` rows ordered by seat, the action stream ordered by
/// `actionOrder`, and the resolved `Player` records keyed by id for username
/// lookup.
struct HandDetailBundle {
    let hand: Hand
    let handPlayers: [HandPlayer]
    let actions: [Action]
    let players: [Player]

    /// Quick lookup so views don't have to scan `players` for every seat.
    var playersById: [Int64: Player] {
        Dictionary(uniqueKeysWithValues: players.compactMap { p in
            p.id.map { ($0, p) }
        })
    }
}
