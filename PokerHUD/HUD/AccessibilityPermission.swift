import AppKit
import ApplicationServices

/// Thin wrapper around the macOS Accessibility permission APIs.
///
/// We use Accessibility to read PokerStars window titles reliably (which
/// CGWindowList can only do with Screen Recording permission — a separate and
/// more intrusive grant). Once Accessibility is granted, the AX window-title
/// lookup in `AccessibilityWindowReader` starts filling in the title field
/// that `PokerStarsWindowDetector` relies on for `findWindowFrame(for:)`
/// name-based binding.
///
/// This helper is intentionally stateless and side-effect-free apart from
/// optionally prompting the user. It is safe to call from any actor.
enum AccessibilityPermission {
    /// Whether this process is currently trusted for Accessibility API access.
    /// Non-prompting — use this for UI state.
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Check trust and optionally prompt the user. macOS shows its standard
    /// "Allow in System Settings" dialog at most once per process lifetime.
    ///
    /// Returns the current trust state after the call. Note: even when `prompt`
    /// is true, the dialog is asynchronous and the user has to act on it in
    /// System Settings, so this will usually return `false` on first call.
    @discardableResult
    static func ensureGranted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: CFDictionary = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open the Accessibility pane in System Settings so the user can toggle
    /// PokerHUD. Uses the modern `x-apple.systempreferences:` URL which works
    /// on macOS 13+ (our minimum is 14).
    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
