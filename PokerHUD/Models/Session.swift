import Foundation
import GRDB

struct Session: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var siteId: Int64
    var tableName: String?
    var gameType: String?
    var stakes: String?
    var startTime: Date
    var endTime: Date?
    var handsPlayed: Int
    var netResult: Double
    var isTournament: Bool
    var tournamentId: Int64?

    static let databaseTableName = "sessions"

    enum Columns: String, ColumnExpression {
        case id, siteId, tableName, gameType, stakes
        case startTime, endTime, handsPlayed, netResult
        case isTournament, tournamentId
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }

    var handsPerHour: Double? {
        guard let duration = duration, duration > 0 else { return nil }
        let hours = duration / 3600
        return Double(handsPlayed) / hours
    }
}

extension Session: Identifiable {}

extension Session {
    static let site = belongsTo(Site.self)
    static let tournament = belongsTo(Tournament.self)
}
