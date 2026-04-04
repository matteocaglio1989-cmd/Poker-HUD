import AppKit
import SwiftUI

/// A floating, transparent NSPanel that hosts a SwiftUI HUD view over the poker table
class HUDPanel: NSPanel {
    private var hostingView: NSHostingView<AnyView>?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Allow mouse for dragging and clicks, but never steal keyboard focus
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
    }

    // Never let the HUD panel become key window (would steal keyboard from main app)
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Set or replace the SwiftUI content of the panel
    func setContent<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]

        // Clear background for hosting view
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        contentView?.subviews.forEach { $0.removeFromSuperview() }
        contentView?.addSubview(hosting)
        hostingView = hosting
    }

    /// Move the panel to a screen position
    func reposition(to point: CGPoint) {
        setFrameOrigin(point)
    }

    /// Resize the panel to fit content
    func resize(to size: CGSize) {
        let origin = frame.origin
        setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

/// Unique key for identifying a HUD panel (table + seat)
struct PanelKey: Hashable {
    let tableId: UUID
    let seatNumber: Int
}
