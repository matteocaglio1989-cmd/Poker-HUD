import Foundation

/// Phase 3 PR4: JSON exporter for Reports + Sessions data.
///
/// Uses `JSONEncoder` with `.prettyPrinted` and `.iso8601` dates so the
/// output is human-readable and round-trips through any JSON consumer.
enum JSONExporter {
    static func playerStatsJSON(_ stats: [PlayerStats]) throws -> Data {
        let payload = stats.map { s in
            JSONPlayerStats(
                player: s.playerName,
                hands: s.handsPlayed,
                vpip: s.vpip,
                pfr: s.pfr,
                threeBet: s.threeBet,
                fourBet: s.fourBet,
                foldTo3Bet: s.foldToThreeBet,
                coldCall: s.coldCall,
                squeeze: s.squeeze,
                af: s.aggressionFactor,
                cbetFlop: s.cbetFlop,
                cbetTurn: s.cbetTurn,
                cbetRiver: s.cbetRiver,
                foldCbetFlop: s.foldToCbetFlop,
                foldCbetTurn: s.foldToCbetTurn,
                foldCbetRiver: s.foldToCbetRiver,
                wtsd: s.wtsd,
                wsd: s.wsd,
                totalWon: s.totalWon,
                bb100: s.bb100,
                playerType: s.playerType.rawValue
            )
        }
        return try encoder().encode(payload)
    }

    static func sessionsJSON(_ sessions: [PlayedSession]) throws -> Data {
        let payload = sessions.map { s in
            JSONSession(
                startTime: s.startTime,
                endTime: s.endTime,
                table: s.tableName,
                stakes: s.stakes,
                durationSeconds: Int(s.duration),
                hands: s.handsPlayed,
                netResult: s.netResult,
                bb100: s.bb100,
                vpip: s.vpip,
                pfr: s.pfr,
                wtsd: s.wtsd,
                wsd: s.wsd,
                isActive: s.isActive
            )
        }
        return try encoder().encode(payload)
    }

    // MARK: - Internals

    private static func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    // Lightweight DTOs so the public Codable surface is stable and
    // doesn't change when PlayerStats / Session gain unrelated fields.

    private struct JSONPlayerStats: Codable {
        let player: String
        let hands: Int
        let vpip: Double
        let pfr: Double
        let threeBet: Double
        let fourBet: Double
        let foldTo3Bet: Double
        let coldCall: Double
        let squeeze: Double
        let af: Double
        let cbetFlop: Double
        let cbetTurn: Double
        let cbetRiver: Double
        let foldCbetFlop: Double
        let foldCbetTurn: Double
        let foldCbetRiver: Double
        let wtsd: Double
        let wsd: Double
        let totalWon: Double
        let bb100: Double
        let playerType: String
    }

    private struct JSONSession: Codable {
        let startTime: Date
        let endTime: Date
        let table: String
        let stakes: String
        let durationSeconds: Int
        let hands: Int
        let netResult: Double
        let bb100: Double
        let vpip: Double
        let pfr: Double
        let wtsd: Double
        let wsd: Double
        let isActive: Bool
    }
}
