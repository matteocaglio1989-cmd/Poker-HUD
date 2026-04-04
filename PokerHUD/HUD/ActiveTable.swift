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
            // 6-max oval layout (relative offsets in points)
            positions = [
                (1, CGPoint(x: 0,   y: 0)),    // Bottom-left
                (2, CGPoint(x: 200, y: 0)),     // Bottom-right
                (3, CGPoint(x: 300, y: 120)),   // Right
                (4, CGPoint(x: 200, y: 240)),   // Top-right
                (5, CGPoint(x: 0,   y: 240)),   // Top-left
                (6, CGPoint(x: -100, y: 120)),  // Left
            ]
        } else {
            // 9-max oval layout
            positions = [
                (1, CGPoint(x: 0,   y: 0)),
                (2, CGPoint(x: 130, y: 0)),
                (3, CGPoint(x: 260, y: 0)),
                (4, CGPoint(x: 340, y: 80)),
                (5, CGPoint(x: 340, y: 180)),
                (6, CGPoint(x: 260, y: 260)),
                (7, CGPoint(x: 130, y: 260)),
                (8, CGPoint(x: 0,   y: 260)),
                (9, CGPoint(x: -80, y: 130)),
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
}
