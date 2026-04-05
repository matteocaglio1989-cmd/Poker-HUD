import SwiftUI

/// Wrapper view that hosts the Standard HUD view — no click interactions
struct HUDContentView: View {
    let playerName: String
    let stats: PlayerStats?
    let configuration: HUDConfiguration

    var body: some View {
        StandardHUDView(
            playerName: playerName,
            stats: stats,
            configuration: configuration
        )
    }
}
