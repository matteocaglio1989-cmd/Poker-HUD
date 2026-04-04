import SwiftUI

/// Wrapper view that hosts StandardHUDView and handles click-to-expand popover
struct HUDContentView: View {
    let playerName: String
    let stats: PlayerStats?
    let configuration: HUDConfiguration

    @State private var showPopover = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Standard compact HUD
            StandardHUDView(
                playerName: playerName,
                stats: stats,
                configuration: configuration
            )
            .onTapGesture {
                showPopover.toggle()
            }

            // Expanded popover overlay
            if showPopover, let stats = stats {
                HUDPopoverView(
                    playerName: playerName,
                    stats: stats,
                    onDismiss: { showPopover = false }
                )
                .offset(x: 0, y: -10) // Shift up slightly above the compact panel
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeInOut(duration: 0.15), value: showPopover)
                .zIndex(1)
            }
        }
    }
}
