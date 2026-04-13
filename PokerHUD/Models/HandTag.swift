import Foundation
import GRDB

struct HandTag: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var handId: Int64
    var tag: String
    var note: String?
    var createdAt: Date

    static let databaseTableName = "hand_tags"

    enum Columns: String, ColumnExpression {
        case id, handId, tag, note, createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension HandTag: Identifiable {}

extension HandTag {
    static let hand = belongsTo(Hand.self)
}

enum CommonHandTag: String, CaseIterable {
    case bluff = "Bluff"
    case valuebet = "Value Bet"
    case badBeat = "Bad Beat"
    case bigPot = "Big Pot"
    case review = "Review"
    case mistake = "Mistake"
    case goodPlay = "Good Play"
    case interesting = "Interesting"
    /// Phase 4 PR3: bookmarks ride on the existing `hand_tags` table to
    /// avoid a schema migration. The toolbar star button in
    /// `HandDetailView` toggles a tag with this exact rawValue.
    case bookmark = "Bookmark"

    var displayName: String {
        rawValue
    }
}
