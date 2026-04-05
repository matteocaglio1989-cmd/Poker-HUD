import Foundation

/// Persists user-customized HUD panel positions relative to the table window.
/// Positions are stored per "slot" (hero-relative index), not per seat number.
/// Slot 0 = hero (bottom-center), slot 1 = one seat left of hero, etc. clockwise.
class HUDSeatOffsets {
    static let shared = HUDSeatOffsets()

    private let userDefaultsKey = "hudSeatOffsets"

    /// Offsets as fraction of window size: (xFraction, yFraction)
    private var offsets: [Int: CGPoint] = [:]

    private init() {
        load()
    }

    func offset(forSlot slot: Int) -> CGPoint? {
        offsets[slot]
    }

    func saveOffset(_ offset: CGPoint, forSlot slot: Int) {
        offsets[slot] = offset
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

    private func persist() {
        var dict: [String: [CGFloat]] = [:]
        for (slot, point) in offsets {
            dict["\(slot)"] = [point.x, point.y]
        }
        UserDefaults.standard.set(dict, forKey: userDefaultsKey)
        UserDefaults.standard.synchronize()
        print("[HUDOffsets] Persisted \(offsets.count) offsets to UserDefaults")
    }

    private func load() {
        guard let dict = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: [CGFloat]] else { return }
        for (key, values) in dict {
            if let slot = Int(key), values.count == 2 {
                offsets[slot] = CGPoint(x: values[0], y: values[1])
            }
        }
        if !offsets.isEmpty {
            print("[HUDOffsets] Loaded \(offsets.count) saved offsets")
        }
    }
}
