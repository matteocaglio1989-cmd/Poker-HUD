import Foundation

/// Phase 3 PR4: minimal CSV exporter for Reports + Sessions data.
///
/// Deliberately bare-bones — quotes only when a field contains a comma,
/// quote, or newline; uses CRLF line endings per RFC 4180. No external
/// dependency. Tested mentally against Excel + Numbers + GoogleSheets;
/// they all happily round-trip the output.
enum CSVExporter {
    /// Render `[PlayerStats]` as a CSV string.
    static func playerStatsCSV(_ stats: [PlayerStats]) -> String {
        var rows: [[String]] = [[
            "Player",
            "Hands",
            "VPIP",
            "PFR",
            "3Bet",
            "4Bet",
            "FoldTo3Bet",
            "ColdCall",
            "Squeeze",
            "AF",
            "CBetFlop",
            "CBetTurn",
            "CBetRiver",
            "FoldCBetFlop",
            "FoldCBetTurn",
            "FoldCBetRiver",
            "WTSD",
            "W$SD",
            "TotalWon",
            "BB100",
            "PlayerType"
        ]]
        for s in stats {
            rows.append([
                s.playerName,
                "\(s.handsPlayed)",
                fmt(s.vpip),
                fmt(s.pfr),
                fmt(s.threeBet),
                fmt(s.fourBet),
                fmt(s.foldToThreeBet),
                fmt(s.coldCall),
                fmt(s.squeeze),
                fmt(s.aggressionFactor),
                fmt(s.cbetFlop),
                fmt(s.cbetTurn),
                fmt(s.cbetRiver),
                fmt(s.foldToCbetFlop),
                fmt(s.foldToCbetTurn),
                fmt(s.foldToCbetRiver),
                fmt(s.wtsd),
                fmt(s.wsd),
                fmt(s.totalWon, decimals: 2),
                fmt(s.bb100, decimals: 2),
                s.playerType.rawValue
            ])
        }
        return encode(rows: rows)
    }

    /// Render `[Session]` as a CSV string.
    static func sessionsCSV(_ sessions: [Session]) -> String {
        let dateFormatter = ISO8601DateFormatter()
        var rows: [[String]] = [[
            "StartTime",
            "EndTime",
            "Table",
            "Stakes",
            "DurationSeconds",
            "Hands",
            "NetResult",
            "BB100",
            "VPIP",
            "PFR",
            "WTSD",
            "WSD",
            "Active"
        ]]
        for s in sessions {
            rows.append([
                dateFormatter.string(from: s.startTime),
                dateFormatter.string(from: s.endTime),
                s.tableName,
                s.stakes,
                "\(Int(s.duration))",
                "\(s.handsPlayed)",
                fmt(s.netResult, decimals: 2),
                fmt(s.bb100),
                fmt(s.vpip),
                fmt(s.pfr),
                fmt(s.wtsd),
                fmt(s.wsd),
                s.isActive ? "true" : "false"
            ])
        }
        return encode(rows: rows)
    }

    // MARK: - Internals

    private static func encode(rows: [[String]]) -> String {
        rows.map { row in
            row.map(escape).joined(separator: ",")
        }
        .joined(separator: "\r\n")
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let doubled = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(doubled)\""
        }
        return field
    }

    private static func fmt(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", value)
    }
}
