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

        // Build action list and track each player's running total commitment
        // (in chips actually put into the pot, post-refund). This replaces
        // the old "sum action.amount" shortcut, which was broken for three
        // reasons stacked on top of each other: raise lines captured the
        // raise-increment instead of the raise-to total, blind posts
        // weren't counted, and "Uncalled bet returned" lines were ignored
        // entirely. Fixing this one loop corrects every downstream value
        // (totalBet / netResult / replayer pot / replayer stacks).
        var actions: [ActionData] = []
        var actionOrder = 0
        var totalCommitments: [String: Double] = [:]
        for username in playerSeats.values {
            totalCommitments[username] = 0.0
        }

        // Streets dict isn't ordered, so walk them in poker order so the
        // per-street commitment reset happens in the right sequence and
        // `actionOrder` is monotonic across the whole hand.
        for street in ["PREFLOP", "FLOP", "TURN", "RIVER"] {
            guard let streetLines = streets[street] else { continue }

            // Per-street commitment tracker. Reset to 0 at every street
            // boundary — then seeded with blind/ante posts on PREFLOP
            // only, since those are the "chips already in front of the
            // player" before any voluntary preflop action happens.
            var commitmentsThisStreet: [String: Double] = [:]
            for username in playerSeats.values {
                commitmentsThisStreet[username] = 0.0
            }
            if street == "PREFLOP" {
                seedBlindAndAnteCommitments(
                    from: lines,
                    into: &commitmentsThisStreet
                )
            }

            for line in streetLines {
                // Uncalled bet refund: emit a virtual UNCALLED_REFUND
                // action so the replayer reverses the chip movement
                // visibly, and subtract the amount from the raiser's
                // street commitment so totalBet ends up correct.
                if let refund = parseUncalledBet(from: line) {
                    commitmentsThisStreet[refund.username, default: 0] -= refund.amount
                    actions.append(ActionData(
                        username: refund.username,
                        street: street,
                        actionOrder: actionOrder,
                        actionType: ActionType.uncalledRefund.rawValue,
                        amount: refund.amount,
                        potBefore: nil,
                        potAfter: nil
                    ))
                    actionOrder += 1
                    continue
                }

                guard let action = parseAction(
                    from: line,
                    street: street,
                    order: actionOrder,
                    commitmentsThisStreet: &commitmentsThisStreet
                ) else { continue }

                actions.append(action)
                actionOrder += 1
            }

            // Flush this street's net commitments into the grand total.
            for (username, committed) in commitmentsThisStreet {
                totalCommitments[username, default: 0] += committed
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

        // Calculate player results. `totalCommitments` was populated by
        // the per-street commitment tracker above, which correctly
        // accounts for blinds, antes, raise-to totals (not the increment
        // PokerStars prints first), and uncalled bet refunds. `totalWon`
        // is filled in from the `collected` lines parsed below.
        var playerResults: [String: (bet: Double, won: Double)] = [:]
        for username in playerSeats.values {
            playerResults[username] = (bet: totalCommitments[username] ?? 0.0, won: 0.0)
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

    /// Parse one voluntary action line. The returned `ActionData.amount`
    /// is the chip delta this action adds to the pot, **not** the raw
    /// number printed by PokerStars — this distinction matters for
    /// raises, where PokerStars prints `raises INCREMENT to TOTAL` and
    /// we need to subtract the player's previous street commitment from
    /// `TOTAL` to get the actual chips they added.
    ///
    /// Mutates `commitmentsThisStreet` in place so the next action's
    /// delta computation sees the updated running total.
    ///
    /// Returns `nil` for non-action lines (blinds, antes, uncalled bet
    /// returns, shows, collected, etc.) — those are handled elsewhere.
    private func parseAction(
        from line: String,
        street: String,
        order: Int,
        commitmentsThisStreet: inout [String: Double]
    ) -> ActionData? {
        // Folds and checks don't move chips; emit with amount = 0 and
        // leave commitments untouched.
        for (keyword, actionType) in [("folds", "FOLD"), ("checks", "CHECK")] {
            if line.contains(": \(keyword)") {
                let username = line.components(separatedBy: ": \(keyword)").first ?? ""
                return ActionData(
                    username: username.trimmingCharacters(in: .whitespaces),
                    street: street,
                    actionOrder: order,
                    actionType: actionType,
                    amount: 0.0,
                    potBefore: nil,
                    potAfter: nil
                )
            }
        }

        // "raises X to Y" — Y is the new street commitment for the
        // raiser; delta = Y - their previous street commitment. This
        // is the critical fix: the old regex captured X (the raise
        // increment above the previous bet level) which systematically
        // under-counted whenever a player raised on top of any prior
        // action, and became catastrophically wrong when the raise
        // was an overbet later partially uncalled.
        let raiseToPattern = #"^([^:]+): raises [\$€£]?[\d.]+ to [\$€£]?([\d.]+)"#
        if let regex = try? NSRegularExpression(pattern: raiseToPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let userRange = Range(match.range(at: 1), in: line),
           let totalRange = Range(match.range(at: 2), in: line),
           let raiseToTotal = Double(line[totalRange]) {

            let username = String(line[userRange]).trimmingCharacters(in: .whitespaces)
            let previous = commitmentsThisStreet[username] ?? 0.0
            let delta = max(0.0, raiseToTotal - previous)
            commitmentsThisStreet[username] = raiseToTotal
            return ActionData(
                username: username,
                street: street,
                actionOrder: order,
                actionType: "RAISE",
                amount: delta,
                potBefore: nil,
                potAfter: nil
            )
        }

        // "bets X" — X is the chips the player is adding on top of
        // their current street commitment. For a post-flop bet this is
        // usually the player's entire street commitment (they had 0 in
        // before betting), so the delta and the printed amount are the
        // same.
        let betPattern = #"^([^:]+): bets [\$€£]?([\d.]+)"#
        if let regex = try? NSRegularExpression(pattern: betPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let userRange = Range(match.range(at: 1), in: line),
           let amountRange = Range(match.range(at: 2), in: line),
           let amount = Double(line[amountRange]) {

            let username = String(line[userRange]).trimmingCharacters(in: .whitespaces)
            commitmentsThisStreet[username, default: 0] += amount
            return ActionData(
                username: username,
                street: street,
                actionOrder: order,
                actionType: "BET",
                amount: amount,
                potBefore: nil,
                potAfter: nil
            )
        }

        // "calls X" — X is the delta chips the player puts in to match
        // the current bet, so we add it straight to their street
        // commitment.
        let callPattern = #"^([^:]+): calls [\$€£]?([\d.]+)"#
        if let regex = try? NSRegularExpression(pattern: callPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let userRange = Range(match.range(at: 1), in: line),
           let amountRange = Range(match.range(at: 2), in: line),
           let amount = Double(line[amountRange]) {

            let username = String(line[userRange]).trimmingCharacters(in: .whitespaces)
            commitmentsThisStreet[username, default: 0] += amount
            return ActionData(
                username: username,
                street: street,
                actionOrder: order,
                actionType: "CALL",
                amount: amount,
                potBefore: nil,
                potAfter: nil
            )
        }

        return nil
    }

    /// Seed the preflop street's commitment tracker with any blinds
    /// and antes that were posted before voluntary action started.
    /// Without this, the SB poster's `totalBet` would be short by the
    /// SB amount whenever they limp-fold, the BB by the BB amount, and
    /// so on — visible as a wrong `netResult` on the Dashboard session
    /// summary and the Hand Detail footer.
    private func seedBlindAndAnteCommitments(
        from lines: [String],
        into commitments: inout [String: Double]
    ) {
        // `posts small blind €0.01`, `posts big blind €0.02`, `posts
        // the ante €0.001`, `posts small & big blinds €0.03` (dead
        // blind when a new player sits out and returns).
        let postPattern = #"^([^:]+): posts (?:small blind|big blind|the ante|small & big blinds) [\$€£]?([\d.]+)"#
        guard let regex = try? NSRegularExpression(pattern: postPattern) else { return }

        for line in lines {
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let userRange = Range(match.range(at: 1), in: line),
                  let amountRange = Range(match.range(at: 2), in: line),
                  let amount = Double(line[amountRange]) else { continue }

            let username = String(line[userRange]).trimmingCharacters(in: .whitespaces)
            commitments[username, default: 0] += amount
        }
    }

    /// Parse an `Uncalled bet (€3.04) returned to logitech6942` line.
    /// Emitted by PokerStars when an all-in raise is only partially
    /// called; the surplus is refunded to the raiser. The parser
    /// treats this as a virtual `UNCALLED_REFUND` action (see
    /// `ActionType.uncalledRefund` in Models/Action.swift) so the
    /// replayer can reverse the chip movement in its animation.
    private func parseUncalledBet(from line: String) -> (username: String, amount: Double)? {
        let pattern = #"^Uncalled bet \([\$€£]?([\d.]+)\) returned to (.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let amountRange = Range(match.range(at: 1), in: line),
              let userRange = Range(match.range(at: 2), in: line),
              let amount = Double(line[amountRange]) else {
            return nil
        }
        let username = String(line[userRange]).trimmingCharacters(in: .whitespaces)
        return (username: username, amount: amount)
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
