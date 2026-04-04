import SwiftUI
import AppKit

/// Fixes the macOS SwiftUI bug where text fields in sheets don't accept keyboard input.
/// The sheet window needs to explicitly become the key window for text fields to work.
struct FocusFixModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Find the sheet window and make it key
                    if let window = NSApp.keyWindow ?? NSApp.windows.last(where: { $0.isVisible && $0.level == .modalPanel }) {
                        window.makeKey()
                    }
                    // Also try making the frontmost sheet key
                    for window in NSApp.windows.reversed() {
                        if window.isVisible && window.isSheet {
                            window.makeKey()
                            break
                        }
                    }
                }
            }
    }
}

extension View {
    /// Apply this to sheet content to fix text field keyboard input on macOS
    func fixSheetFocus() -> some View {
        modifier(FocusFixModifier())
    }
}
