import Foundation

/// Aggregated player statistics computed from hand history
struct PlayerStats: Identifiable {
    let id: Int64  // player ID
    let playerId: Int64
    let playerName: String

    // Sample size
    let handsPlayed: Int

    // Preflop stats
    let vpip: Double          // Voluntarily Put $ In Pot
    let pfr: Double           // Pre-Flop Raise
    let threeBet: Double      // 3-Bet percentage
    let fourBet: Double       // 4-Bet percentage
    let foldToThreeBet: Double
    let coldCall: Double      // Call after raise
    let squeeze: Double       // 3-bet when facing raise and caller(s)

    // Postflop aggression
    let aggressionFactor: Double  // (Bet + Raise) / Call
    let aggressionPercentage: Double

    // C-Betting
    let cbetFlop: Double
    let cbetTurn: Double
    let cbetRiver: Double
    let foldToCbetFlop: Double
    let foldToCbetTurn: Double
    let foldToCbetRiver: Double

    // Showdown
    let wtsd: Double          // Went To ShowDown
    let wsd: Double           // Won at ShowDown (when went to SD)

    // Results
    let totalWon: Double
    let bb100: Double         // Big blinds won per 100 hands

    var id_computed: Int64 { playerId }

    init(
        playerId: Int64,
        playerName: String,
        handsPlayed: Int,
        vpip: Double,
        pfr: Double,
        threeBet: Double,
        fourBet: Double,
        foldToThreeBet: Double,
        coldCall: Double,
        squeeze: Double,
        aggressionFactor: Double,
        aggressionPercentage: Double,
        cbetFlop: Double,
        cbetTurn: Double,
        cbetRiver: Double,
        foldToCbetFlop: Double,
        foldToCbetTurn: Double,
        foldToCbetRiver: Double,
        wtsd: Double,
        wsd: Double,
        totalWon: Double,
        bb100: Double
    ) {
        self.id = playerId
        self.playerId = playerId
        self.playerName = playerName
        self.handsPlayed = handsPlayed
        self.vpip = vpip
        self.pfr = pfr
        self.threeBet = threeBet
        self.fourBet = fourBet
        self.foldToThreeBet = foldToThreeBet
        self.coldCall = coldCall
        self.squeeze = squeeze
        self.aggressionFactor = aggressionFactor
        self.aggressionPercentage = aggressionPercentage
        self.cbetFlop = cbetFlop
        self.cbetTurn = cbetTurn
        self.cbetRiver = cbetRiver
        self.foldToCbetFlop = foldToCbetFlop
        self.foldToCbetTurn = foldToCbetTurn
        self.foldToCbetRiver = foldToCbetRiver
        self.wtsd = wtsd
        self.wsd = wsd
        self.totalWon = totalWon
        self.bb100 = bb100
    }

    /// Classify player type based on VPIP/PFR
    var playerType: PlayerType {
        guard handsPlayed >= 50 else { return .unknown }

        let vpipThreshold = 25.0
        let pfrThreshold = 18.0

        if vpip < 15 && pfr < 12 {
            return .nit
        } else if vpip < 20 && pfr >= pfrThreshold {
            return .tag
        } else if vpip >= vpipThreshold && pfr >= pfrThreshold {
            return .lag
        } else if vpip >= 35 && pfr < 15 {
            return .fish
        } else if vpip < 10 && pfr < 8 {
            return .rock
        } else if vpip >= 40 && pfr >= 30 {
            return .maniac
        }

        return .unknown
    }
}

/// Individual HUD stat definition
struct HUDStat: Identifiable {
    let id = UUID()
    let name: String
    let abbreviation: String
    let value: Double
    let sampleSize: Int
    let colorCode: StatColorCode

    enum StatColorCode {
        case red
        case orange
        case yellow
        case green
        case blue
        case neutral

        var color: String {
            switch self {
            case .red: return "#FF3B30"
            case .orange: return "#FF9500"
            case .yellow: return "#FFCC00"
            case .green: return "#34C759"
            case .blue: return "#007AFF"
            case .neutral: return "#8E8E93"
            }
        }
    }

    func formattedValue(decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", value)
    }
}
