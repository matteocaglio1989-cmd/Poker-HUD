import SwiftUI

/// Compact trial pill shown at the bottom of the sidebar column in
/// `MainView` while the user is on the free trial. Clicking "Upgrade"
/// opens the paywall as a sheet so they can subscribe without waiting for
/// the trial to run out.
///
/// The vertical layout (icon + label on top, full-width button below) is
/// tuned for the ~200 pt sidebar slot. The static `format(remaining:)`
/// helper below is also reused by `SettingsView` and `PaywallView` for
/// consistent "Xh Ym" / "Ym Zs" formatting — do not rename it.
struct TrialBannerView: View {
    let remainingSeconds: TimeInterval
    @State private var showingPaywall: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Free trial")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(Self.format(remaining: remainingSeconds))
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
