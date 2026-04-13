import SwiftUI

/// Reactive state for a single HUD panel.
@MainActor
final class HUDPanelState: ObservableObject {
    @Published var stats: PlayerStats?
    @Published var lastUpdated: Date = .distantPast
    /// When true, the panel shows the full stat grid instead of the
    /// compact VPIP/PFR/3Bet line. Toggled by double-clicking the
    /// HUD label.
    @Published var isExpanded: Bool = false

    init(stats: PlayerStats? = nil) {
        self.stats = stats
    }
}

/// Hosts either the compact `StandardHUDView` or the full
/// `ExpandedHUDView`, driven by `HUDPanelState.isExpanded`. A
/// double-click toggles between the two. The `onExpandToggle`
/// callback notifies the owning `HUDManager` so it can resize the
/// `HUDPanel` to fit the new content.
struct HUDContentView: View {
    let playerName: String
    @ObservedObject var state: HUDPanelState
    let configuration: HUDConfiguration

    /// Called when the expanded state changes so `HUDManager` can
    /// resize the `HUDPanel` to fit the new content size.
    var onExpandToggle: ((Bool) -> Void)?

    @State private var flashing: Bool = false

    var body: some View {
        Group {
            if state.isExpanded {
                ExpandedHUDView(
                    playerName: playerName,
                    stats: state.stats,
                    configuration: configuration
                )
            } else {
                StandardHUDView(
                    playerName: playerName,
                    stats: state.stats,
                    configuration: configuration
                )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.green, lineWidth: 2)
                .opacity(flashing ? 1 : 0)
                .animation(.easeOut(duration: 0.35), value: flashing)
        )
        .onTapGesture(count: 2) {
            state.isExpanded.toggle()
            onExpandToggle?(state.isExpanded)
        }
        .task(id: state.lastUpdated) {
            guard state.lastUpdated != .distantPast else { return }
            flashing = true
            try? await Task.sleep(nanoseconds: 700_000_000)
            flashing = false
        }
    }
}
