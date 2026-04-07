import SwiftUI

/// Thin banner shown at the top of MainView while the user is on the free
/// trial. Clicking "Upgrade" opens the paywall as a sheet so they can
/// subscribe without waiting for the trial to run out.
struct TrialBannerView: View {
    let remainingSeconds: TimeInterval
    @State private var showingPaywall: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .foregroundStyle(.orange)
            Text("Free trial: \(Self.format(remaining: remainingSeconds)) left")
                .font(.callout)
                .fontWeight(.medium)
            Spacer()
            Button("Upgrade") { showingPaywall = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Color.orange.opacity(0.15)
                .overlay(Divider(), alignment: .bottom)
        )
        .sheet(isPresented: $showingPaywall) {
            PaywallView(presentedAsSheet: true)
                .frame(minWidth: 720, minHeight: 640)
        }
    }

    /// Format a remaining-seconds value as e.g. "2h 14m" or "14m 03s".
    static func format(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return "\(seconds)s"
        }
    }
}
