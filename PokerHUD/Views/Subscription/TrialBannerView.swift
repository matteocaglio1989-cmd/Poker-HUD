import SwiftUI

/// Compact trial pill shown at the bottom of the sidebar column in
/// `MainView` while the user is on the free trial. Clicking "Upgrade"
/// opens the paywall as a sheet so they can subscribe without waiting
/// for the counter to run out.
///
/// The counter now reads "N hands left" — the trial budget is 100
/// imported hands (see `TrialPolicy.totalHands`). The static
/// `format(remainingHands:)` helper is reused by `SettingsView` and
/// `PaywallView` for consistent phrasing; do not rename it without
/// updating both call sites.
struct TrialBannerView: View {
    let remainingHands: Int
    @State private var showingPaywall: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "tray.2.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Free trial")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(Self.format(remainingHands: remainingHands))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button {
                showingPaywall = true
            } label: {
                Text("Upgrade")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Color.orange.opacity(0.15)
                .overlay(Divider(), alignment: .top)
        )
        .sheet(isPresented: $showingPaywall) {
            PaywallView(presentedAsSheet: true)
                .frame(minWidth: 720, minHeight: 640)
        }
    }

    /// Format a remaining-hand count as e.g. "42 hands" or "1 hand".
    /// Negative and zero values collapse to "0 hands" so the UI never
    /// shows a nonsense number if the counter briefly overshoots.
    static func format(remainingHands: Int) -> String {
        let clamped = max(0, remainingHands)
        return clamped == 1 ? "1 hand" : "\(clamped) hands"
    }
}
