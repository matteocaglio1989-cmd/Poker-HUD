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
            // `lastInsertedRowID` is non-optional and always populated after
            // a successful insert; the guard is belt-and-braces against a
            // future GRDB schema regression.
            guard let handId = hand.id else {
                throw HandRepositoryError.missingPersistedID("Hand")
            }

            for i in 0..<players.count {
                var player = players[i]
                player.handId = handId
                try player.insert(db)
                players[i] = player
            }

            for var action in actions {
                action.handId = handId
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

    func fetchRecent(limit: Int = 100, moneyType: String? = nil) throws -> [Hand] {
        try dbManager.reader.read { db in
            var request = Hand
                .order(Hand.Columns.playedAt.desc)
            if let moneyType = moneyType {
                request = request.filter(Hand.Columns.moneyType == moneyType)
            }
            return try request.limit(limit).fetchAll(db)
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

    // MARK: - Hero results (batch)

    /// Fetch the hero's `netResult` for a batch of hand IDs in a single
    /// query. Returns a dictionary keyed by `Hand.id` so the caller can
    /// look up each hand's P/L in O(1). Used by `HandReplayerView` to
    /// display a profit/loss column in the hand list without N+1 queries.
    func fetchHeroResults(forHandIds handIds: [Int64]) throws -> [Int64: Double] {
        guard !handIds.isEmpty else { return [:] }
        return try dbManager.reader.read { db in
            let idList = handIds.map { "\($0)" }.joined(separator: ",")
            let rows = try Row.fetchAll(db, sql: """
                SELECT handId, netResult FROM hand_players
                WHERE handId IN (\(idList)) AND isHero = 1
            """)
            var result: [Int64: Double] = [:]
            for row in rows {
                let handId: Int64 = row["handId"]
                let net: Double = row["netResult"]
                result[handId] = net
            }
            return result
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

    // MARK: - Tags & bookmarks (Phase 4 PR3)

    /// Insert a new tag row. Mutates `tag.id` to the generated rowid so the
    /// caller can keep a stable reference for delete-on-tap.
    func addTag(_ tag: inout HandTag) throws {
        try dbManager.writer.write { db in
            try tag.insert(db)
        }
    }

    /// All tags currently attached to a hand, ordered with newest first
    /// so the chip list reads chronologically.
    func fetchTags(forHandId handId: Int64) throws -> [HandTag] {
        try dbManager.reader.read { db in
            try HandTag
                .filter(HandTag.Columns.handId == handId)
                .order(HandTag.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Delete a single tag by id. Used by both the chip-tap delete and
    /// the bookmark star toggle (which deletes the row tagged
    /// `"Bookmark"` for the active hand).
    func removeTag(id: Int64) throws {
        try dbManager.writer.write { db in
            _ = try HandTag.deleteOne(db, key: id)
        }
    }

    /// Hands that carry at least one `tag = "Bookmark"` row, ordered
    /// newest-first. Powers the "Bookmarked" filter in `HandReplayerView`.
    /// Joining a hasMany relation can produce duplicate hand rows when a
    /// hand has multiple matching tags, so the result is deduplicated by
    /// id in Swift before returning.
    func fetchBookmarkedHands(limit: Int = 200) throws -> [Hand] {
        let hands = try dbManager.reader.read { db in
            try Hand
                .joining(required: Hand.tags
                    .filter(HandTag.Columns.tag == CommonHandTag.bookmark.rawValue))
                .order(Hand.Columns.playedAt.desc)
                .fetchAll(db)
        }
        return Self.deduplicate(hands, limit: limit)
    }

    /// Hands that carry at least one tag of any kind (used by the
    /// "Tagged" filter pill).
    func fetchTaggedHands(limit: Int = 200) throws -> [Hand] {
        let hands = try dbManager.reader.read { db in
            try Hand
                .joining(required: Hand.tags)
                .order(Hand.Columns.playedAt.desc)
                .fetchAll(db)
        }
        return Self.deduplicate(hands, limit: limit)
    }

    /// Deduplicate a hand list by id (preserving order) and trim to
    /// `limit`. Used after a hasMany join that can produce one row per
    /// matching child relation.
    private static func deduplicate(_ hands: [Hand], limit: Int) -> [Hand] {
        var seen: Set<Int64> = []
        var result: [Hand] = []
        result.reserveCapacity(min(hands.count, limit))
        for hand in hands {
            guard let id = hand.id else { continue }
            if seen.insert(id).inserted {
                result.append(hand)
                if result.count >= limit { break }
            }
        }
        return result
    }
}

/// Errors thrown by `HandRepository` when GRDB insert post-conditions aren't
/// met. Separate from `ImportEngineError` so the repository stays decoupled
/// from the import pipeline.
enum HandRepositoryError: LocalizedError {
    case missingPersistedID(String)

    var errorDescription: String? {
        switch self {
        case .missingPersistedID(let entity):
            return "Database did not return a row id for \(entity) after insert"
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
