import SwiftUI

/// Reactive state for a single HUD panel.
///
/// `HUDManager` creates one of these per panel and keeps a reference. When
/// new hands come in, it mutates `stats` and `lastUpdated` on the state
/// object, which drives a SwiftUI re-render of the corresponding
/// `HUDContentView` without recreating the underlying `NSHostingView`.
///
/// Prior to this, every stats refresh called `HUDPanel.setContent(...)`,
/// which tore down the hosting view and any in-progress SwiftUI state
/// (including animation timers). That made the "real-time" feedback
/// requested for Phase 2 impossible to implement visually — a flash border
/// could never survive the view being destroyed and rebuilt on every
/// update. Centralising state in an `ObservableObject` fixes that and
/// doubles as a mild performance win (no per-refresh view tree rebuild).
@MainActor
final class HUDPanelState: ObservableObject {
    @Published var stats: PlayerStats?
    /// Timestamp of the last time `stats` was refreshed. A change to this
    /// value is what the `HUDContentView` flash-border modifier keys off of.
    /// Initialised to `.distantPast` so the first real update is treated as
    /// a change (and not swallowed by SwiftUI's equality check).
    @Published var lastUpdated: Date = .distantPast

    init(stats: PlayerStats? = nil) {
        self.stats = stats
    }
}

/// Hosts the `StandardHUDView` and drives its flash-border animation off
/// `HUDPanelState.lastUpdated`. Thin wrapper, intentionally — all real
/// rendering lives in `StandardHUDView`.
struct HUDContentView: View {
    let playerName: String
    @ObservedObject var state: HUDPanelState
    let configuration: HUDConfiguration

    @State private var flashing: Bool = false

    var body: some View {
        StandardHUDView(
            playerName: playerName,
            stats: state.stats,
            configuration: configuration
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.green, lineWidth: 2)
                .opacity(flashing ? 1 : 0)
                .animation(.easeOut(duration: 0.35), value: flashing)
        )
        .task(id: state.lastUpdated) {
            // Skip the initial appearance (distantPast) so we don't flash
            // every panel on creation.
            guard state.lastUpdated != .distantPast else { return }
            flashing = true
            try? await Task.sleep(nanoseconds: 700_000_000)
            flashing = false
        }
    }
}
