import AppKit
import SwiftUI

/// A floating, transparent NSPanel that hosts a SwiftUI HUD view over the poker table.
/// Supports dragging to reposition — uses a position monitor to detect moves.
class HUDPanel: NSPanel {
    private var hostingView: NSHostingView<AnyView>?
    private var positionMonitor: Timer?
    private var lastSavedOrigin: CGPoint = .zero

    /// Called when the user drags this panel to a new position
    var onDragEnd: ((CGPoint) -> Void)?

    /// The slot index (hero-relative seat position) for saving offsets
    var slotIndex: Int = 0

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        lastSavedOrigin = contentRect.origin
        configure()
        startPositionMonitor()
    }

    private func configure() {
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Poll position every 200ms to detect user drags
    private func startPositionMonitor() {
        positionMonitor = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let currentOrigin = self.frame.origin
            let dx = abs(currentOrigin.x - self.lastSavedOrigin.x)
            let dy = abs(currentOrigin.y - self.lastSavedOrigin.y)
            if dx > 5 || dy > 5 {
                self.lastSavedOrigin = currentOrigin
                print("[HUDPanel] Slot \(self.slotIndex) moved to (\(Int(currentOrigin.x)), \(Int(currentOrigin.y)))")
                self.onDragEnd?(currentOrigin)
            }
        }
    }

    /// Update the saved origin without triggering a save (used by HUDManager reposition)
    func updateLastSavedOrigin() {
        lastSavedOrigin = frame.origin
    }

    func setContent<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]

        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        contentView?.subviews.forEach { $0.removeFromSuperview() }
        contentView?.addSubview(hosting)
        hostingView = hosting
    }

    func reposition(to point: CGPoint) {
        setFrameOrigin(point)
        lastSavedOrigin = point
    }

    func resize(to size: CGSize) {
        let origin = frame.origin
        setFrame(NSRect(origin: origin, size: size), display: true)
    }

    deinit {
        positionMonitor?.invalidate()
    }
}

/// Unique key for identifying a HUD panel (table + seat)
struct PanelKey: Hashable {
    let tableId: UUID
    let seatNumber: Int
}
