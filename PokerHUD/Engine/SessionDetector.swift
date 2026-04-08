import Foundation
import GRDB

/// Session model used by both the Dashboard "Active Session" card and the
/// new Phase 3 PR3 Sessions tab. A session is a contiguous run of the
/// hero's hands where consecutive timestamps are no more than 30 minutes
/// apart — the standard "tracker session" definition.
///
/// Same struct shape as the older `SessionSummary` from
/// `DashboardView.swift`, lifted up to a top-level type so the new
/// `SessionsView` and `SessionDetailView` don't have to import the
/// dashboard. Once the dashboard is updated to consume `Session` instead
/// of its own private `SessionSummary`, the duplicate can be deleted.
struct Session: Identifiable, Hashable {
    let id: UUID = UUID()
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

    /// Per-hand cumulative profit/loss series, used by `SessionDetailView`'s
    /// Swift Charts BB/100 line. Empty for sessions returned by the bulk
    /// `recentSessions(...)` query — populated only when the caller asks
    /// for a specific session via `SessionDetector.detail(for:)`.
    var handPoints: [SessionHandPoint] = []

    var durationFormatted: String {
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
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

/// One hand inside a session. The `cumulativeNet` field carries the
/// running profit/loss in real money so the chart can plot a profit
/// curve without re-summing on every redraw.
struct SessionHandPoint: Identifiable, Hashable {
    let id = UUID()
    let playedAt: Date
    let netResult: Double
    let cumulativeNet: Double
    let handIndex: Int
}

/// Session detection service. Extracts the 30-minute-gap grouping
/// algorithm previously inlined in `DashboardView.computeActiveSession()`
/// and exposes both the original "active session" use case AND the new
/// "all historical sessions" query needed by the Sessions tab.
///
/// All methods are synchronous; they're cheap (one indexed read on
/// `hands.playedAt` plus a tight Swift loop) and called from background
/// `Task` blocks by the views.
struct SessionDetector {
    /// Maximum gap between two consecutive hands within the same session.
    /// 30 minutes matches every major poker tracker convention.
    static let sessionGap: TimeInterval = 30 * 60

    private let dbManager: DatabaseManager

    init(databaseManager: DatabaseManager = .shared) {
        self.dbManager = databaseManager
    }

    /// Return every historical session for the hero, newest first. Limit
    /// caps the underlying hand window — 5000 hands is plenty for the
    /// current dataset and bounds the worst-case runtime.
    func allSessions(heroPlayerName: String? = nil, limit: Int = 5000) throws -> [Session] {
        let rows = try fetchHeroHands(playerName: heroPlayerName, limit: limit)
        guard !rows.isEmpty else { return [] }
        return groupIntoSessions(rows: rows)
    }

    /// Find the single most-recent session containing the given hand
    /// timestamp. Used by `SessionDetailView` when the caller has a
    /// `Session` from the list view but needs the per-hand point series
    /// for charting.
    func detail(for session: Session, heroPlayerName: String? = nil) throws -> Session {
        let rows = try fetchHeroHands(
            playerName: heroPlayerName,
            from: session.startTime,
            to: session.endTime,
            limit: 5000
        )
        guard !rows.isEmpty else { return session }

        // Build cumulative profit points in chronological order (oldest first
        // — the SQL returns DESC so we reverse).
        let chronological = rows.reversed()
        var cumulative: Double = 0
        var points: [SessionHandPoint] = []
        for (idx, row) in chronological.enumerated() {
            let netResult: Double = row["netResult"]
            let playedAt: Date = row["playedAt"]
            cumulative += netResult
            points.append(SessionHandPoint(
                playedAt: playedAt,
                netResult: netResult,
                cumulativeNet: cumulative,
                handIndex: idx + 1
            ))
        }

        var enriched = session
        enriched.handPoints = points
        return enriched
    }

    // MARK: - Private

    private func fetchHeroHands(
        playerName: String?,
        from: Date? = nil,
        to: Date? = nil,
        limit: Int
    ) throws -> [Row] {
        try dbManager.reader.read { db in
            var sql = """
                SELECT h.id, h.playedAt, h.tableName, h.bigBlind, h.smallBlind, h.gameType,
                       hp.netResult, hp.vpip, hp.pfr, hp.wentToShowdown, hp.wonAtShowdown
                FROM hand_players hp
                INNER JOIN hands h ON h.id = hp.handId
                INNER JOIN players p ON p.id = hp.playerId
                WHERE hp.isHero = 1
                """
            var arguments: [DatabaseValueConvertible] = []

            if let playerName = playerName, !playerName.isEmpty {
                sql += " AND p.username = ?"
                arguments.append(playerName)
            }
            if let from = from {
                sql += " AND h.playedAt >= ?"
                arguments.append(from)
            }
            if let to = to {
                sql += " AND h.playedAt <= ?"
                arguments.append(to)
            }

            sql += " ORDER BY h.playedAt DESC LIMIT ?"
            arguments.append(limit)

            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    /// Walk the hero's hands (newest first) and split into sessions
    /// whenever consecutive timestamps are more than `sessionGap` apart.
    /// Returns sessions newest-first (matching the visual ordering of the
    /// Sessions tab list).
    private func groupIntoSessions(rows: [Row]) -> [Session] {
        var sessions: [Session] = []
        var currentBucket: [Row] = []

        func flushCurrent() {
            guard !currentBucket.isEmpty else { return }
            if let session = makeSession(from: currentBucket) {
                sessions.append(session)
            }
            currentBucket.removeAll(keepingCapacity: true)
        }

        for (i, row) in rows.enumerated() {
            if i == 0 {
                currentBucket.append(row)
                continue
            }
            let prev: Date = currentBucket.last!["playedAt"]
            let cur: Date = row["playedAt"]
            // Rows are DESC, so prev > cur. A "gap" means prev minus cur > 30min.
            if prev.timeIntervalSince(cur) > Self.sessionGap {
                flushCurrent()
            }
            currentBucket.append(row)
        }
        flushCurrent()

        return sessions
    }

    private func makeSession(from rows: [Row]) -> Session? {
        guard !rows.isEmpty else { return nil }

        // Rows are DESC: rows.first = newest = endTime, rows.last = oldest = startTime
        let endTime: Date = rows.first!["playedAt"]
        let startTime: Date = rows.last!["playedAt"]
        let duration = endTime.timeIntervalSince(startTime)

        let handsPlayed = rows.count
        var totalNet: Double = 0
        var totalBB: Double = 0
        var vpipCount = 0
        var pfrCount = 0
        var wtsdCount = 0
        var wsdCount = 0
        for row in rows {
            let net: Double = row["netResult"]
            let bb: Double = row["bigBlind"]
            let vpip: Bool = row["vpip"]
            let pfr: Bool = row["pfr"]
            let wtsd: Bool = row["wentToShowdown"]
            let wsd: Bool = row["wonAtShowdown"]
            totalNet += net
            totalBB += bb
            if vpip { vpipCount += 1 }
            if pfr { pfrCount += 1 }
            if wtsd { wtsdCount += 1 }
            if wsd { wsdCount += 1 }
        }
        let avgBB = totalBB / Double(handsPlayed)
        let bb100 = avgBB > 0 ? (totalNet / avgBB) / Double(handsPlayed) * 100 : 0
        let vpipPct = Double(vpipCount) / Double(handsPlayed) * 100
        let pfrPct = Double(pfrCount) / Double(handsPlayed) * 100
        let wtsdPct = Double(wtsdCount) / Double(handsPlayed) * 100
        let wsdPct = wtsdCount > 0 ? Double(wsdCount) / Double(wtsdCount) * 100 : 0
        let isActive = Date().timeIntervalSince(endTime) < Self.sessionGap

        let tableName = rows.first?["tableName"] as? String ?? "Unknown"
        let smallBlind: Double = rows.first?["smallBlind"] ?? 0
        let bigBlind: Double = rows.first?["bigBlind"] ?? 0
        let stakes = "\(smallBlind)/\(bigBlind)"

        return Session(
            tableName: tableName,
            stakes: stakes,
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
}
