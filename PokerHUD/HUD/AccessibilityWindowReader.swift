import AppKit
import ApplicationServices

/// A PokerStars window as seen through the macOS Accessibility API.
/// `frame` is in Cocoa screen coordinates (origin at bottom-left of the main
/// display), matching the convention `PokerStarsWindowDetector` uses for its
/// CGWindowList-derived frames — so the two sources can be merged directly.
struct AXPokerStarsWindow {
    let title: String
    let frame: NSRect
}

/// Reads PokerStars windows via the macOS Accessibility API.
///
/// **Why this exists.** CGWindowList only surfaces window titles when the
/// process has been granted Screen Recording permission. Phase 2 binding
/// (`HUDManager.findWindowFrame`) relies on those titles to match a DB
/// table to the right live window. When titles are empty, binding falls
/// back to an exclusion heuristic that becomes brittle the moment a user
/// opens multiple tables rapidly or closes and reopens one.
///
/// The Accessibility API can read window titles independently of Screen
/// Recording. We enumerate PokerStars processes via `NSWorkspace`, ask the
/// AX app for its `kAXWindowsAttribute`, and return `(title, frame)` pairs
/// that `PokerStarsWindowDetector` then merges into its CGWindowList output.
///
/// **What this is NOT.** This is not a replacement for CGWindowList, and it
/// does not install any `AXObserver`s. Phase 2 keeps CGWindowList as the
/// source of `CGWindowID`s (which the existing binding map uses as keys) and
/// keeps `HUDManager.startPositionTracking`'s 500 ms reposition poll. This
/// reader is purely an *enrichment* path for window titles.
enum AccessibilityWindowReader {
    /// Enumerate all currently-visible PokerStars windows via AX.
    /// Returns an empty array when Accessibility is not granted, so callers
    /// can treat it as "no enrichment available" without branching.
    static func findPokerStarsWindows() -> [AXPokerStarsWindow] {
        guard AccessibilityPermission.isGranted else { return [] }

        var results: [AXPokerStarsWindow] = []
        for app in NSWorkspace.shared.runningApplications {
            // PokerStars ships under several bundle IDs across locales/clients
            // (com.pokerstars.PokerStars, com.pokerstars.eu.PokerStars, etc.).
            // Matching on a lowercased substring catches all of them.
            guard let bundleID = app.bundleIdentifier,
                  bundleID.lowercased().contains("pokerstars") else { continue }
            results.append(contentsOf: readWindows(forPID: app.processIdentifier))
        }
        return results
    }

    // MARK: - AX plumbing

    private static func readWindows(forPID pid: pid_t) -> [AXPokerStarsWindow] {
        let axApp = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else {
            return []
        }

        let screenHeight = NSScreen.main?.frame.height ?? 0

        var out: [AXPokerStarsWindow] = []
        for window in windows {
            guard let title = copyStringAttribute(window, kAXTitleAttribute as CFString),
                  !title.isEmpty else { continue }
            guard let position = copyPointAttribute(window, kAXPositionAttribute as CFString),
                  let size = copySizeAttribute(window, kAXSizeAttribute as CFString) else { continue }

            // AX coordinates have origin at top-left of the main display;
            // Cocoa (and PokerStarsWindowDetector) use bottom-left. Mirror
            // the same flip PokerStarsWindowDetector does for CGWindowList
            // results so merged frames compare directly.
            let flippedY = screenHeight - position.y - size.height
            let frame = NSRect(x: position.x, y: flippedY, width: size.width, height: size.height)

            // Same minimum-size filter as PokerStarsWindowDetector — table
            // windows are always wider than 600 and taller than 400. This
            // discards lobby/chat popups.
            guard frame.width > 600, frame.height > 400 else { continue }

            out.append(AXPokerStarsWindow(title: title, frame: frame))
        }
        return out
    }

    private static func copyStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    /// Extract a `CGPoint` from an AX attribute. The AX framework wraps
    /// points in an opaque `AXValue`; we verify the type ID before the
    /// force-cast so a wrong attribute returns nil instead of crashing.
    private static func copyPointAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let raw = value,
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        // Safe after the AXValue type-ID check above.
        let axValue = raw as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    /// Extract a `CGSize` from an AX attribute — see `copyPointAttribute`.
    private static func copySizeAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let raw = value,
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let axValue = raw as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}
