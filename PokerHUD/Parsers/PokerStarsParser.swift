import Foundation

/// Parser for PokerStars hand history files
class PokerStarsParser: HandHistoryParser {
    let siteName = "PokerStars"

    func canParse(_ text: String) -> Bool {
        text.contains("PokerStars Hand #") || text.contains("PokerStars Zoom Hand #")
    }

    func parse(_ text: String) throws -> [ParsedHand] {
        // Strip BOM if present
        let cleanText = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text

        // Split by hand separator (blank lines between hands)
        let handTexts = cleanText.components(separatedBy: "\n\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return handTexts.compactMap { handText in
            try? parseHand(handText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func parseHand(_ text: String) throws -> ParsedHand? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return nil }

        // Parse header line: "PokerStars Hand #123456789: Hold'em No Limit ($0.50/$1.00 USD) - 2025/01/15 12:34:56 ET"
        let headerLine = lines[0]
        guard let handId = extractHandId(from: headerLine) else {
            throw ParserError.missingHandId
        }

        // Extract game info
        let gameInfo = try parseGameInfo(from: headerLine)
        let playedAt = try parseDate(from: headerLine)

        // Extract table name
        var tableName = "Unknown"
        var tableSize = 9
        if let tableLine = lines.first(where: { $0.hasPrefix("Table '") }) {
            tableName = extractTableName(from: tableLine)
            tableSize = extractTableSize(from: tableLine)
        }

        // Extract tournament ID if present
        var tournamentId: String? = nil
        if headerLine.contains("Tournament #") {
            tournamentId = extractTournamentId(from: headerLine)
        }

        // Parse players
        var playerSeats: [Int: String] = [:]
        var playerStacks: [String: Double] = [:]
        for line in lines {
            if line.hasPrefix("Seat ") && line.contains("in chips") {
                let (seat, username, stack) = try parseSeatInfo(from: line)
                playerSeats[seat] = username
                playerStacks[username] = stack
            }
        }

        guard !playerSeats.isEmpty else {
            throw ParserError.missingPlayerInfo
        }

        // Find button position
        var buttonSeat = 1
        if let buttonLine = lines.first(where: { $0.contains("is the button") }) {
            buttonSeat = extractButtonSeat(from: buttonLine)
        }

        // Calculate positions
        let positions = calculatePositions(seats: playerSeats, buttonSeat: buttonSeat, tableSize: tableSize)

        // Parse actions by street
        let streets = parseStreets(from: lines)

        // Build action list
        var actions: [ActionData] = []
        var actionOrder = 0

        for (street, streetLines) in streets {
            for line in streetLines {
                if let action = parseAction(from: line, street: street, order: actionOrder) {
                    actions.append(action)
                    actionOrder += 1
                }
            }
        }

        // Parse hole cards
        var holeCards: [String: String] = [:]
        var heroName: String? = nil
        for line in lines {
            if line.hasPrefix("Dealt to ") {
                let (username, cards) = parseHoleCards(from: line)
                holeCards[username] = cards
                heroName = username
            }
        }

        // Parse board
        var board: String? = nil
        if let flopLine = lines.first(where: { $0.hasPrefix("*** FLOP ***") }) {
            board = extractBoard(from: flopLine)
        }
        if let turnLine = lines.first(where: { $0.hasPrefix("*** TURN ***") }) {
            let turnBoard = extractBoard(from: turnLine)
            if turnBoard != board {
                board = turnBoard
            }
        }
        if let riverLine = lines.first(where: { $0.hasPrefix("*** RIVER ***") }) {
            let riverBoard = extractBoard(from: riverLine)
            if riverBoard != board {
                board = riverBoard
            }
        }

        // Calculate player results
        var playerResults: [String: (bet: Double, won: Double)] = [:]
        for username in playerSeats.values {
            playerResults[username] = (bet: 0.0, won: 0.0)
        }

        // Sum bets from actions
        for action in actions {
            if let current = playerResults[action.username] {
                playerResults[action.username] = (bet: current.bet + action.amount, won: current.won)
            }
        }

        // Parse pot and rake from summary
        var potTotal = 0.0
        var rake = 0.0
        if let potLine = lines.first(where: { $0.hasPrefix("Total pot ") }) {
            (potTotal, rake) = parsePotAndRake(from: potLine)
        }

        // Parse winners
        var winners: [String: Double] = [:]
        for line in lines {
            if line.contains(" collected ") {
                let (username, amount) = parseWinner(from: line)
                winners[username, default: 0.0] += amount
            }
        }

        for (username, amount) in winners {
            if var current = playerResults[username] {
                current.won = amount
                playerResults[username] = current
            }
        }

        // Check who went to showdown
        var showdownPlayers = Set<String>()
        if let showdownIndex = lines.firstIndex(where: { $0.hasPrefix("*** SHOW DOWN ***") }) {
            for line in lines[showdownIndex...] {
                if line.contains(": shows ") {
                    if let username = line.components(separatedBy: ": shows ").first {
                        showdownPlayers.insert(username)
                    }
                }
            }
        }

        // Build player data
        var players: [PlayerData] = []
        for (seat, username) in playerSeats.sorted(by: { $0.key < $1.key }) {
            let stack = playerStacks[username] ?? 0.0
            let result = playerResults[username] ?? (bet: 0.0, won: 0.0)
            let netResult = result.won - result.bet
            let wentToShowdown = showdownPlayers.contains(username)
            let wonAtShowdown = wentToShowdown && (result.won > 0)

            players.append(PlayerData(
                username: username,
                seat: seat,
                position: positions[seat],
                holeCards: holeCards[username],
                isHero: username == heroName,
                startingStack: stack,
                totalBet: result.bet,
                totalWon: result.won,
                netResult: netResult,
                wentToShowdown: wentToShowdown,
                wonAtShowdown: wonAtShowdown
            ))
        }

        let handData = HandData(
            handId: handId,
            siteName: siteName,
            tableName: tableName,
            gameType: gameInfo.gameType,
            limitType: gameInfo.limitType,
            tableSize: tableSize,
            smallBlind: gameInfo.smallBlind,
            bigBlind: gameInfo.bigBlind,
            ante: gameInfo.ante,
            board: board,
            potTotal: potTotal,
            rake: rake,
            playedAt: playedAt,
            rawText: text,
            tournamentId: tournamentId
        )

        return ParsedHand(hand: handData, players: players, actions: actions)
    }

    // MARK: - Helper Methods

    private func extractHandId(from line: String) -> String? {
        let pattern = #"Hand #(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range])
    }

    private func extractTournamentId(from line: String) -> String? {
        let pattern = #"Tournament #(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range])
    }

    private func parseGameInfo(from line: String) throws -> (gameType: String, limitType: String, smallBlind: Double, bigBlind: Double, ante: Double) {
        var gameType = "HOLDEM"
        if line.contains("Omaha") {
            gameType = "OMAHA"
        }

        var limitType = "NL"
        if line.contains("No Limit") {
            limitType = "NL"
        } else if line.contains("Pot Limit") {
            limitType = "PL"
        } else if line.contains("Limit") {
            limitType = "FL"
        }

        // Extract blinds: ($0.50/$1.00) or (€0.01/€0.02 EUR) or (0.50/1.00)
        let pattern = #"[\$€£]?([\d.]+)/[\$€£]?([\d.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let sbRange = Range(match.range(at: 1), in: line),
              let bbRange = Range(match.range(at: 2), in: line),
              let sb = Double(line[sbRange]),
              let bb = Double(line[bbRange]) else {
            throw ParserError.missingGameInfo
        }

        // Check for ante
        var ante = 0.0
        let antePattern = #"Ante [\$€£]?([\d.]+)"#
        if let anteRegex = try? NSRegularExpression(pattern: antePattern),
           let anteMatch = anteRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let anteRange = Range(anteMatch.range(at: 1), in: line) {
            ante = Double(line[anteRange]) ?? 0.0
        }

        return (gameType: gameType, limitType: limitType, smallBlind: sb, bigBlind: bb, ante: ante)
    }

    private func parseDate(from line: String) throws -> Date {
        // Format 1: 2025/01/15 12:34:56 ET
        // Format 2: 2026/04/04 13:00:40 UTC [2026/04/04 9:00:40 ET]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"

        // Try UTC timestamp first (more precise)
        let utcPattern = #"(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) UTC"#
        if let regex = try? NSRegularExpression(pattern: utcPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            formatter.timeZone = TimeZone(identifier: "UTC")
            if let date = formatter.date(from: String(line[range])) {
                return date
            }
        }

        // Fall back to ET timestamp
        let etPattern = #"(\d{4}/\d{2}/\d{2} \d{1,2}:\d{2}:\d{2}) ET"#
        if let regex = try? NSRegularExpression(pattern: etPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            formatter.timeZone = TimeZone(identifier: "America/New_York")
            if let date = formatter.date(from: String(line[range])) {
                return date
            }
        }

        // Last resort: any datetime pattern
        let anyPattern = #"(\d{4}/\d{2}/\d{2} \d{1,2}:\d{2}:\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: anyPattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            throw ParserError.invalidDate
        }

        formatter.timeZone = TimeZone(identifier: "America/New_York")
        guard let date = formatter.date(from: String(line[range])) else {
            throw ParserError.invalidDate
        }
        return date
    }

    private func extractTableName(from line: String) -> String {
        // Table 'TableName' 9-max
        let pattern = #"Table '([^']+)'"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return "Unknown"
        }
        return String(line[range])
    }

    private func extractTableSize(from line: String) -> Int {
        if line.contains("2-max") { return 2 }
        if line.contains("6-max") { return 6 }
        if line.contains("9-max") { return 9 }
        return 9 // default
    }

    private func parseSeatInfo(from line: String) throws -> (seat: Int, username: String, stack: Double) {
        // Seat 1: PlayerName ($100.00 in chips)
        // Seat 1: PlayerName (€2 in chips) is sitting out
        let pattern = #"Seat (\d+): ([^\(]+) \([\$€£]?([\d.]+) in chips\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let seatRange = Range(match.range(at: 1), in: line),
              let usernameRange = Range(match.range(at: 2), in: line),
              let stackRange = Range(match.range(at: 3), in: line),
              let seat = Int(line[seatRange]),
              let stack = Double(line[stackRange]) else {
            throw ParserError.missingPlayerInfo
        }

        let username = String(line[usernameRange]).trimmingCharacters(in: .whitespaces)
        return (seat: seat, username: username, stack: stack)
    }

    private func extractButtonSeat(from line: String) -> Int {
        // Seat #5 is the button
        let pattern = #"Seat #(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let seat = Int(line[range]) else {
            return 1
        }
        return seat
    }

    private func calculatePositions(seats: [Int: String], buttonSeat: Int, tableSize: Int) -> [Int: String] {
        let sortedSeats = seats.keys.sorted()
        guard let buttonIndex = sortedSeats.firstIndex(of: buttonSeat) else {
            return [:]
        }

        var positions: [Int: String] = [:]
        let playerCount = sortedSeats.count

        // Get seats in order after button
        var orderedSeats: [Int] = []
        for i in 1..<playerCount {
            let index = (buttonIndex + i) % playerCount
            orderedSeats.append(sortedSeats[index])
        }

        // Button
        positions[buttonSeat] = "BTN"

        if playerCount == 2 {
            positions[orderedSeats[0]] = "BB"
        } else {
            positions[orderedSeats[0]] = "SB"
            positions[orderedSeats[1]] = "BB"

            if playerCount > 2 {
                let remaining = playerCount - 3
                for i in 0..<remaining {
                    let seat = orderedSeats[i + 2]
                    if playerCount <= 6 {
                        positions[seat] = i == remaining - 1 ? "CO" : "MP"
                    } else {
                        // 9-max positions
                        switch remaining - i {
                        case 1: positions[seat] = "CO"
                        case 2: positions[seat] = "HJ"
                        case 3: positions[seat] = "LJ"
                        case 4: positions[seat] = "MP"
                        case 5: positions[seat] = "UTG+2"
                        case 6: positions[seat] = "UTG+1"
                        default: positions[seat] = "UTG"
                        }
                    }
                }
            }
        }

        return positions
    }

    private func parseStreets(from lines: [String]) -> [String: [String]] {
        var streets: [String: [String]] = [:]
        var currentStreet = "PREFLOP"
        var streetLines: [String] = []

        for line in lines {
            if line.hasPrefix("*** HOLE CARDS ***") {
                currentStreet = "PREFLOP"
                streetLines = []
            } else if line.hasPrefix("*** FLOP ***") {
                streets["PREFLOP"] = streetLines
                currentStreet = "FLOP"
                streetLines = []
            } else if line.hasPrefix("*** TURN ***") {
                streets["FLOP"] = streetLines
                currentStreet = "TURN"
                streetLines = []
            } else if line.hasPrefix("*** RIVER ***") {
                streets["TURN"] = streetLines
                currentStreet = "RIVER"
                streetLines = []
            } else if line.hasPrefix("*** SHOW DOWN ***") || line.hasPrefix("*** SUMMARY ***") {
                streets[currentStreet] = streetLines
                break
            } else {
                streetLines.append(line)
            }
        }

        return streets
    }

    private func parseAction(from line: String, street: String, order: Int) -> ActionData? {
        let actionPatterns = [
            ("folds", "FOLD", 0.0),
            ("checks", "CHECK", 0.0)
        ]

        for (keyword, actionType, defaultAmount) in actionPatterns {
            if line.contains(": \(keyword)") {
                let username = line.components(separatedBy: ": \(keyword)").first ?? ""
                return ActionData(
                    username: username.trimmingCharacters(in: .whitespaces),
                    street: street,
                    actionOrder: order,
                    actionType: actionType,
                    amount: defaultAmount,
                    potBefore: nil,
                    potAfter: nil
                )
            }
        }

        // Parse call/bet/raise with amount (handles $, €, £)
        let amountPattern = #": (calls|bets|raises) [\$€£]?([\d.]+)"#
        if let regex = try? NSRegularExpression(pattern: amountPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let actionRange = Range(match.range(at: 1), in: line),
           let amountRange = Range(match.range(at: 2), in: line),
           let amount = Double(line[amountRange]) {

            let actionType = String(line[actionRange]).uppercased()
            let username = line.components(separatedBy: ": ").first ?? ""

            return ActionData(
                username: username.trimmingCharacters(in: .whitespaces),
                street: street,
                actionOrder: order,
                actionType: actionType == "RAISES" ? "RAISE" : actionType == "BETS" ? "BET" : "CALL",
                amount: amount,
                potBefore: nil,
                potAfter: nil
            )
        }

        return nil
    }

    private func parseHoleCards(from line: String) -> (username: String, cards: String) {
        // Dealt to PlayerName [Ah Kd]
        let components = line.replacingOccurrences(of: "Dealt to ", with: "")
            .components(separatedBy: " [")
        let username = components[0]
        let cards = components.count > 1 ?
            components[1].replacingOccurrences(of: "]", with: "") : ""
        return (username: username, cards: cards)
    }

    private func extractBoard(from line: String) -> String? {
        let pattern = #"\[([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range])
    }

    private func parsePotAndRake(from line: String) -> (pot: Double, rake: Double) {
        // Total pot $100 | Rake $5  OR  Total pot €0.06 | Rake €0
        var pot = 0.0
        var rake = 0.0

        let potPattern = #"Total pot [\$€£]?([\d.]+)"#
        if let regex = try? NSRegularExpression(pattern: potPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            pot = Double(line[range]) ?? 0.0
        }

        let rakePattern = #"Rake [\$€£]?([\d.]+)"#
        if let regex = try? NSRegularExpression(pattern: rakePattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            rake = Double(line[range]) ?? 0.0
        }

        return (pot: pot, rake: rake)
    }

    private func parseWinner(from line: String) -> (username: String, amount: Double) {
        // PlayerName collected $100 from pot  OR  collected (€0.06)
        let pattern = #"([^\s]+) collected [\(\$€£]*([\d.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let usernameRange = Range(match.range(at: 1), in: line),
              let amountRange = Range(match.range(at: 2), in: line),
              let amount = Double(line[amountRange]) else {
            return (username: "", amount: 0.0)
        }

        return (username: String(line[usernameRange]), amount: amount)
    }
}
