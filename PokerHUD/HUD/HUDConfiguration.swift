import Foundation
import SwiftUI

/// HUD appearance and behavior configuration
struct HUDConfiguration: Codable {
    var opacity: Double
    var fontSize: Double
    var showPlayerType: Bool
    var statsToDisplay: [HUDStat]
    var colorThresholds: HUDColorThresholds

    static let standard = HUDConfiguration(
        opacity: 0.75,
        fontSize: 12,
        showPlayerType: true,
        statsToDisplay: [.vpip, .pfr, .threeBet, .aggressionFactor, .wtsd, .wsd, .hands],
        colorThresholds: .default
    )

    static let compact = HUDConfiguration(
        opacity: 0.80,
        fontSize: 11,
        showPlayerType: true,
        statsToDisplay: [.vpip, .pfr, .threeBet, .aggressionFactor, .hands],
        colorThresholds: .default
    )
}

/// Stats available for HUD display
enum HUDStat: String, Codable, CaseIterable, Identifiable {
    case vpip = "VPIP"
    case pfr = "PFR"
    case threeBet = "3Bet"
    case fourBet = "4Bet"
    case aggressionFactor = "AF"
    case wtsd = "WTSD"
    case wsd = "W$SD"
    case cbetFlop = "CBet"
    case foldToCbet = "F2CB"
    case hands = "Hands"
    case bb100 = "BB/100"

    var id: String { rawValue }

    var label: String { rawValue }

    func value(from stats: PlayerStats) -> String {
        switch self {
        case .vpip: return String(format: "%.0f", stats.vpip)
        case .pfr: return String(format: "%.0f", stats.pfr)
        case .threeBet: return String(format: "%.0f", stats.threeBet)
        case .fourBet: return String(format: "%.0f", stats.fourBet)
        case .aggressionFactor: return String(format: "%.1f", stats.aggressionFactor)
        case .wtsd: return String(format: "%.0f", stats.wtsd)
        case .wsd: return String(format: "%.0f", stats.wsd)
        case .cbetFlop: return String(format: "%.0f", stats.cbetFlop)
        case .foldToCbet: return String(format: "%.0f", stats.foldToCbetFlop)
        case .hands: return "\(stats.handsPlayed)"
        case .bb100: return String(format: "%.1f", stats.bb100)
        }
    }

    func color(from stats: PlayerStats, thresholds: HUDColorThresholds) -> Color {
        switch self {
        case .vpip: return thresholds.colorForVPIP(stats.vpip)
        case .pfr: return thresholds.colorForPFR(stats.pfr)
        case .threeBet: return thresholds.colorFor3Bet(stats.threeBet)
        case .aggressionFactor: return thresholds.colorForAF(stats.aggressionFactor)
        case .bb100: return stats.bb100 >= 0 ? .green : .red
        default: return .white
        }
    }
}

/// Color thresholds for stat highlighting
struct HUDColorThresholds: Codable {
    var vpipTight: Double    // below = red (nit)
    var vpipLoose: Double    // above = blue (fish)
    var pfrTight: Double
    var pfrLoose: Double
    var threeBetLow: Double
    var threeBetHigh: Double
    var afPassive: Double
    var afAggressive: Double

    static let `default` = HUDColorThresholds(
        vpipTight: 15, vpipLoose: 35,
        pfrTight: 10, pfrLoose: 25,
        threeBetLow: 5, threeBetHigh: 12,
        afPassive: 1.5, afAggressive: 3.5
    )

    func colorForVPIP(_ value: Double) -> Color {
        if value < vpipTight { return .red }
        if value <= vpipLoose { return .green }
        return .cyan
    }

    func colorForPFR(_ value: Double) -> Color {
        if value < pfrTight { return .red }
        if value <= pfrLoose { return .green }
        return .cyan
    }

    func colorFor3Bet(_ value: Double) -> Color {
        if value < threeBetLow { return .red }
        if value <= threeBetHigh { return .green }
        return .cyan
    }

    func colorForAF(_ value: Double) -> Color {
        if value < afPassive { return .red }
        if value <= afAggressive { return .green }
        return .cyan
    }
}
