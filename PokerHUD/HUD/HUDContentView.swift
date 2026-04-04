import SwiftUI

/// Wrapper view that hosts Standard or Graphical HUD and handles click-to-expand popover
struct HUDContentView: View {
    let playerName: String
    let stats: PlayerStats?
    let configuration: HUDConfiguration

    @State private var showPopover = false
    @State private var useGraphical = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main HUD view
            Group {
                if useGraphical {
                    GraphicalHUDView(
                        playerName: playerName,
                        stats: stats,
                        configuration: configuration
                    )
                } else {
                    StandardHUDView(
                        playerName: playerName,
                        stats: stats,
                        configuration: configuration
                    )
                }
            }
            .onTapGesture {
                showPopover.toggle()
            }
            .onLongPressGesture {
                useGraphical.toggle()
            }

            // Expanded popover overlay
            if showPopover, let stats = stats {
                HUDPopoverView(
                    playerName: playerName,
                    stats: stats,
                    onDismiss: { showPopover = false }
                )
                .offset(x: 0, y: -10)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeInOut(duration: 0.15), value: showPopover)
                .zIndex(1)
            }
        }
    }
}
