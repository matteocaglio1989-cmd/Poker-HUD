import SwiftUI

/// Phase 4 PR2: visual themes for the replayer's poker table. Each case
/// supplies a felt colour, rail colour, accent colour for active seats,
/// and a card-back tint. The user picks a theme from a small popover in
/// `HandDetailView`'s table panel; the choice is persisted to
/// `UserDefaults` under `replayer.tableTheme`.
enum TableTheme: String, CaseIterable, Identifiable {
    case classicGreen
    case dark
    case wood
    case tournament

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classicGreen: return "Classic Green"
        case .dark:         return "Dark"
        case .wood:         return "Wood"
        case .tournament:   return "Tournament"
        }
    }

    /// Felt colour — the inner table surface.
    var feltColor: Color {
        switch self {
        case .classicGreen: return Color(red: 0.05, green: 0.42, blue: 0.20)
        case .dark:         return Color(red: 0.10, green: 0.12, blue: 0.16)
        case .wood:         return Color(red: 0.30, green: 0.18, blue: 0.10)
        case .tournament:   return Color(red: 0.45, green: 0.05, blue: 0.10)
        }
    }

    /// Rail colour — the outer ring framing the felt.
    var railColor: Color {
        switch self {
        case .classicGreen: return Color(red: 0.25, green: 0.16, blue: 0.08)
        case .dark:         return Color(red: 0.20, green: 0.22, blue: 0.27)
        case .wood:         return Color(red: 0.18, green: 0.10, blue: 0.04)
        case .tournament:   return Color(red: 0.20, green: 0.05, blue: 0.05)
        }
    }

    /// Accent ring drawn around the active seat.
    var accentColor: Color {
        switch self {
        case .classicGreen: return .yellow
        case .dark:         return .cyan
        case .wood:         return .orange
        case .tournament:   return .yellow
        }
    }

    /// Card-back tint used for face-down hole cards.
    var cardBackColor: Color {
        switch self {
        case .classicGreen: return Color(red: 0.08, green: 0.22, blue: 0.55)
        case .dark:         return Color(red: 0.20, green: 0.20, blue: 0.30)
        case .wood:         return Color(red: 0.55, green: 0.10, blue: 0.10)
        case .tournament:   return Color(red: 0.10, green: 0.10, blue: 0.30)
        }
    }

    /// Foreground colour for player labels (so they stay legible against
    /// the chosen felt).
    var labelColor: Color {
        switch self {
        case .classicGreen: return .white
        case .dark:         return .white
        case .wood:         return .white
        case .tournament:   return .white
        }
    }
}

/// Lightweight `UserDefaults` wrapper used by `HandDetailView` to remember
/// the user's last theme pick. Default is Classic Green.
enum TableThemeStorage {
    private static let key = "replayer.tableTheme"

    static func load() -> TableTheme {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let theme = TableTheme(rawValue: raw) else {
            return .classicGreen
        }
        return theme
    }

    static func save(_ theme: TableTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: key)
    }
}
