import Foundation

/// Represents a poker table being actively tracked by the HUD
struct ActiveTable: Identifiable, Codable {
    let id: UUID
    var tableName: String
    var site: String
    var stakes: String
    var tableSize: Int // 6 or 9
    var seatAssignments: [SeatAssignment]
    var origin: CGPoint // table window position on screen
    var isHUDVisible: Bool

    init(
        id: UUID = UUID(),
        tableName: String,
        site: String = "PokerStars",
        stakes: String = "0.5/1.0",
        tableSize: Int = 6,
        seatAssignments: [SeatAssignment] = [],
        origin: CGPoint = .zero,
        isHUDVisible: Bool = false
    ) {
        self.id = id
        self.tableName = tableName
        self.site = site
        self.stakes = stakes
        self.tableSize = tableSize
        self.seatAssignments = seatAssignments.isEmpty
            ? SeatAssignment.defaultLayout(for: tableSize)
            : seatAssignments
        self.origin = origin
        self.isHUDVisible = isHUDVisible
    }
}

/// Maps a seat number to a player and screen position
struct SeatAssignment: Identifiable, Codable {
    let id: UUID
    var seatNumber: Int
    var playerName: String?
    var offset: CGPoint // HUD position relative to table origin

    init(id: UUID = UUID(), seatNumber: Int, playerName: String? = nil, offset: CGPoint = .zero) {
        self.id = id
        self.seatNumber = seatNumber
        self.playerName = playerName
        self.offset = offset
    }

    /// Generate default oval seat layout positions for a given table size
    static func defaultLayout(for tableSize: Int) -> [SeatAssignment] {
        let positions: [(Int, CGPoint)]

        if tableSize <= 6 {
            // 6-max PokerStars-style layout (seat positions matching table UI)
            // Seats arranged: 1=top-left, 2=top-right, 3=right, 4=bottom-right, 5=bottom-center, 6=left
            positions = [
                (1, CGPoint(x: 20,  y: 300)),   // Top-left
                (2, CGPoint(x: 380, y: 340)),   // Top-right
                (3, CGPoint(x: 440, y: 150)),   // Right
                (4, CGPoint(x: 380, y: -20)),   // Bottom-right
                (5, CGPoint(x: 140, y: -40)),   // Bottom-center (hero)
                (6, CGPoint(x: -40, y: 150)),   // Left
            ]
        } else {
            // 9-max layout
            positions = [
                (1, CGPoint(x: 20,  y: 320)),   // Top-left
                (2, CGPoint(x: 200, y: 360)),   // Top-center
                (3, CGPoint(x: 400, y: 320)),   // Top-right
                (4, CGPoint(x: 460, y: 190)),   // Right
                (5, CGPoint(x: 400, y: 40)),    // Bottom-right
                (6, CGPoint(x: 280, y: -20)),   // Bottom-center-right
                (7, CGPoint(x: 140, y: -20)),   // Bottom-center-left (hero)
                (8, CGPoint(x: 20,  y: 40)),    // Bottom-left
                (9, CGPoint(x: -40, y: 190)),   // Left
            ]
        }

        return positions.map { SeatAssignment(seatNumber: $0.0, offset: $0.1) }
    }
}

/// Result returned by the HUD-aware import pipeline
struct HUDImportResult {
    let handsImported: Int       // newly imported hands
    let handsParsed: Int         // total hands found in file (including duplicates)
    let affectedTableNames: Set<String>
    let affectedPlayerNames: Set<String>
    let errors: [ImportError]
    /// Latest seat layout per table name (for auto-creating HUD tables)
    let tableSeats: [String: [TableSeatInfo]]
}

/// Player-to-seat mapping from a parsed hand
struct TableSeatInfo {
    let seatNumber: Int
    let playerName: String
    let isHero: Bool
    let tableSize: Int
    let stakes: String
}
