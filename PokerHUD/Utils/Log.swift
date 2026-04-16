import Foundation
import os

/// Central structured logger that replaces the scattered `print()` calls
/// in the codebase. Uses Apple's unified logging system (`os.Logger`),
/// which automatically respects Release vs Debug — `.debug` and `.info`
/// messages are suppressed in App Store builds, while `.error` and
/// `.fault` are always captured and visible in Console.app.
///
/// Usage:
///     Log.hud.debug("Bound table \(id) to window \(windowID)")
///     Log.importer.error("Parse failed: \(error)")
///
/// Filter in Console.app with `subsystem:com.pokerhud.app`, or by
/// category, e.g. `subsystem:com.pokerhud.app category:hud`.
///
/// Why a central enum instead of scattered `Logger(...)` calls: one place
/// to tweak subsystem/category, no duplicated constants, and a single
/// grep target when we want to audit all logging call sites.
enum Log {
    private static let subsystem = "com.pokerhud.app"

    /// App lifecycle, auth state changes, top-level routing.
    static let app          = Logger(subsystem: subsystem, category: "app")

    /// HUD panel layout, window binding, accessibility-driven positioning.
    static let hud          = Logger(subsystem: subsystem, category: "hud")

    /// Hand history parsing and database import pipeline.
    static let importer     = Logger(subsystem: subsystem, category: "import")

    /// Subscription manager, StoreKit, trial counter, paywall.
    static let subscription = Logger(subsystem: subsystem, category: "subscription")

    /// Polling file watcher that detects new hand history files on disk.
    static let filewatcher  = Logger(subsystem: subsystem, category: "filewatcher")

    /// Screen-recording permission requests and PokerStars window detection.
    static let ax           = Logger(subsystem: subsystem, category: "accessibility")
}
