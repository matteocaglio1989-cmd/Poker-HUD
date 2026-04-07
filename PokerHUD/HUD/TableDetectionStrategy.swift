import Foundation

/// Protocol for pluggable table detection strategies.
///
/// Phase 2 detection flows through `PokerStarsWindowDetector.findTableWindows()`,
/// which now enriches its CGWindowList results with titles read via
/// `AccessibilityWindowReader` when Screen Recording permission is unavailable.
/// `ManualTableDetection` below remains as the explicit "no auto-detect"
/// option for users who prefer to add tables by hand in `TableSetupView`.
protocol TableDetectionStrategy {
    /// Detect active poker tables
    func detectTables() -> [DetectedTable]

    /// Whether this strategy can auto-detect (vs manual setup)
    var isAutomatic: Bool { get }
}

/// Information about a detected poker table
struct DetectedTable {
    let tableName: String
    let site: String
    let stakes: String
    let tableSize: Int
    let windowFrame: CGRect
    let seatPositions: [Int: CGPoint] // seat number -> screen position
}

/// Manual table detection (no-op) — tables are added by user in TableSetupView
class ManualTableDetection: TableDetectionStrategy {
    let isAutomatic = false

    func detectTables() -> [DetectedTable] {
        return [] // Manual mode: user adds tables via UI
    }
}
