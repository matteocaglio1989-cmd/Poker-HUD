import Foundation

/// Persists user-customized HUD panel positions relative to the table window.
///
/// Positions are stored per (tableSize, slot) pair, where "slot" is the
/// hero-relative visual index computed by
/// `(seatNumber - heroSeat + maxSeats) % maxSeats` in `HUDManager`. Slot 0
/// is always the hero at bottom-center; slot 1 is one seat counter-clockwise
/// (visually "to the left of" hero), and so on clockwise around the table.
///
/// Prior to this rewrite, offsets were keyed by slot alone, which meant 6-max
/// and 9-max overrides collided (e.g. a dragged 6-max slot 3 would snap
/// 9-max's slot 3 to the wrong place). The keying is now table-size aware and
/// legacy (slot-only) keys are migrated once on first load to the 6-max
/// bucket, which is the historically dominant case.
///
/// Note: the default fractional offsets in `default6Max` / `default9Max`
/// must not be changed casually — they were tuned in commit `cf705c0` to
/// match the actual PokerStars visual layout after the slot-direction
/// formula in `HUDManager` was finally nailed down. Breaking either value
/// here will visibly misplace HUD panels for every user.
class HUDSeatOffsets {
    static let shared = HUDSeatOffsets()

    /// Current on-disk schema version. Bump this when changing the storage
    /// layout and add a migration branch in `load()`.
    private static let schemaVersion = 2
    /// Same UserDefaults key across schema versions — the migration
    /// rewrites the value in place in the new format rather than moving
    /// to a new key.
    private let userDefaultsKey = "hudSeatOffsets"
    private let schemaVersionKey = "hudSeatOffsetsVersion"

    /// Offsets as fraction of window size, keyed by (tableSize, slot).
    private var offsets: [OffsetKey: CGPoint] = [:]

    private init() {
        load()
    }

    struct OffsetKey: Hashable {
        let tableSize: Int
        let slot: Int
    }

    func offset(forTableSize tableSize: Int, slot: Int) -> CGPoint? {
        offsets[OffsetKey(tableSize: tableSize, slot: slot)]
    }

    func saveOffset(_ offset: CGPoint, forTableSize tableSize: Int, slot: Int) {
        offsets[OffsetKey(tableSize: tableSize, slot: slot)] = offset
        persist()
    }

    func absoluteToFractional(_ point: CGPoint, windowFrame: NSRect) -> CGPoint {
        guard windowFrame.width > 0, windowFrame.height > 0 else { return point }
        return CGPoint(
            x: (point.x - windowFrame.origin.x) / windowFrame.width,
            y: (point.y - windowFrame.origin.y) / windowFrame.height
        )
    }

    func fractionalToAbsolute(_ fraction: CGPoint, windowFrame: NSRect) -> CGPoint {
        CGPoint(
            x: windowFrame.origin.x + fraction.x * windowFrame.width,
            y: windowFrame.origin.y + fraction.y * windowFrame.height
        )
    }

    var hasCustomOffsets: Bool { !offsets.isEmpty }

    // Slot 0=hero(bottom), 1=left, 2=top-left, 3=top-center, 4=top-right, 5=right
    static let default6Max: [Int: CGPoint] = [
        0: CGPoint(x: 0.40, y: 0.10),   // Hero: bottom-center
        1: CGPoint(x: 0.02, y: 0.35),   // Left of hero
        2: CGPoint(x: 0.05, y: 0.65),   // Top-left
        3: CGPoint(x: 0.38, y: 0.80),   // Top-center
        4: CGPoint(x: 0.70, y: 0.65),   // Top-right
        5: CGPoint(x: 0.72, y: 0.35),   // Right of hero
    ]

    static let default9Max: [Int: CGPoint] = [
        0: CGPoint(x: 0.42, y: 0.10),
        1: CGPoint(x: 0.02, y: 0.22),
        2: CGPoint(x: 0.02, y: 0.42),
        3: CGPoint(x: 0.08, y: 0.65),
        4: CGPoint(x: 0.32, y: 0.78),
        5: CGPoint(x: 0.55, y: 0.78),
        6: CGPoint(x: 0.72, y: 0.65),
        7: CGPoint(x: 0.78, y: 0.42),
        8: CGPoint(x: 0.70, y: 0.22),
    ]

    /// Look up the default fractional offset for a given table size + slot.
    /// Returns a fallback center point if the slot is out of range, which
    /// should only happen if callers miscalculate the slot index.
    static func defaultOffset(forTableSize tableSize: Int, slot: Int) -> CGPoint {
        let table = tableSize <= 6 ? default6Max : default9Max
        return table[slot] ?? CGPoint(x: 0.5, y: 0.5)
    }

    private func persist() {
        // Serialize as ["tableSize:slot" -> [x, y]] so UserDefaults stays on
        // plist-compatible types. Schema version is written alongside so a
        // future bump can detect an old format on load.
        var dict: [String: [CGFloat]] = [:]
        for (key, point) in offsets {
            dict["\(key.tableSize):\(key.slot)"] = [point.x, point.y]
        }
        UserDefaults.standard.set(dict, forKey: userDefaultsKey)
        UserDefaults.standard.set(Self.schemaVersion, forKey: schemaVersionKey)
        print("[HUDOffsets] Persisted \(offsets.count) offsets (schema v\(Self.schemaVersion))")
    }

    private func load() {
        let storedVersion = UserDefaults.standard.integer(forKey: schemaVersionKey)
        // `integer(forKey:)` returns 0 when unset, which for us means "legacy".

        if storedVersion >= Self.schemaVersion {
            loadCurrentSchema()
        } else {
            migrateFromLegacy()
        }

        if !offsets.isEmpty {
            print("[HUDOffsets] Loaded \(offsets.count) saved offsets")
        }
    }

    private func loadCurrentSchema() {
        guard let dict = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: [CGFloat]] else { return }
        for (rawKey, values) in dict {
            guard values.count == 2 else { continue }
            let parts = rawKey.split(separator: ":")
            guard parts.count == 2,
                  let tableSize = Int(parts[0]),
                  let slot = Int(parts[1]) else { continue }
            offsets[OffsetKey(tableSize: tableSize, slot: slot)] = CGPoint(x: values[0], y: values[1])
        }
    }

    /// One-time migration from schema v1 (slot-only keys) to v2 (tableSize:slot).
    /// Legacy entries are assumed to belong to 6-max — historically the
    /// dominant case and the only size a user could sanely have tuned given
    /// the slot-collision bug. The migration runs exactly once, guarded by
    /// `schemaVersionKey`, and rewrites the same UserDefaults key in the
    /// new format before stamping the version.
    private func migrateFromLegacy() {
        defer {
            // Always stamp the version, even if there was nothing to migrate,
            // so we don't re-run this path on every launch.
            UserDefaults.standard.set(Self.schemaVersion, forKey: schemaVersionKey)
        }

        guard let dict = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: [CGFloat]] else {
            return
        }

        var migrated = 0
        for (rawKey, values) in dict {
            guard values.count == 2 else { continue }
            // Legacy keys are plain slot integers like "3". New keys contain
            // a colon. If we already see a colon here the user must have
            // launched a newer build first; keep those as-is.
            if rawKey.contains(":") {
                let parts = rawKey.split(separator: ":")
                if parts.count == 2,
                   let tableSize = Int(parts[0]),
                   let slot = Int(parts[1]) {
                    offsets[OffsetKey(tableSize: tableSize, slot: slot)] = CGPoint(x: values[0], y: values[1])
                }
                continue
            }
            guard let slot = Int(rawKey) else { continue }
            offsets[OffsetKey(tableSize: 6, slot: slot)] = CGPoint(x: values[0], y: values[1])
            migrated += 1
        }

        if migrated > 0 {
            // Rewrite the same key in the new format so we don't need a
            // separate legacy key lying around.
            persist()
            print("[HUDOffsets] Migrated \(migrated) legacy offsets to 6-max bucket")
        }
    }
}
