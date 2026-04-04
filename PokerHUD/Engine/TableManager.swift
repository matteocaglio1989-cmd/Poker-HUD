import Foundation

/// Manages active poker tables and seat assignments for the HUD
class TableManager {
    private(set) var tables: [ActiveTable] = []

    // MARK: - Table CRUD

    /// Add a new table with default seat layout
    @discardableResult
    func addTable(name: String, site: String = "PokerStars", stakes: String = "0.5/1.0", tableSize: Int = 6) -> ActiveTable {
        let table = ActiveTable(
            tableName: name,
            site: site,
            stakes: stakes,
            tableSize: tableSize
        )
        tables.append(table)
        return table
    }

    /// Remove a table by ID
    func removeTable(id: UUID) {
        tables.removeAll { $0.id == id }
    }

    /// Update a table
    func updateTable(_ table: ActiveTable) {
        if let index = tables.firstIndex(where: { $0.id == table.id }) {
            tables[index] = table
        }
    }

    // MARK: - Seat Assignment

    /// Assign a player to a seat on a table
    func assignPlayer(_ playerName: String, toSeat seatNumber: Int, on tableId: UUID) {
        guard let tableIndex = tables.firstIndex(where: { $0.id == tableId }) else { return }
        if let seatIndex = tables[tableIndex].seatAssignments.firstIndex(where: { $0.seatNumber == seatNumber }) {
            tables[tableIndex].seatAssignments[seatIndex].playerName = playerName
        }
    }

    /// Clear a seat assignment
    func clearSeat(_ seatNumber: Int, on tableId: UUID) {
        guard let tableIndex = tables.firstIndex(where: { $0.id == tableId }) else { return }
        if let seatIndex = tables[tableIndex].seatAssignments.firstIndex(where: { $0.seatNumber == seatNumber }) {
            tables[tableIndex].seatAssignments[seatIndex].playerName = nil
        }
    }

    // MARK: - Matching

    /// Match a hand's table name to an active table
    func matchHandToTable(tableName: String) -> ActiveTable? {
        // Exact match first
        if let table = tables.first(where: { $0.tableName == tableName }) {
            return table
        }
        // Partial match (table name might have extra info like seat numbers)
        return tables.first { tableName.contains($0.tableName) || $0.tableName.contains(tableName) }
    }

    /// Get all assigned player names for a table
    func playersAtTable(_ table: ActiveTable) -> [String] {
        table.seatAssignments.compactMap { $0.playerName }
    }

    /// Get all assigned player names across all tables
    func allTrackedPlayers() -> Set<String> {
        Set(tables.flatMap { playersAtTable($0) })
    }
}
