import SwiftUI
import StoreKit

/// Full-window paywall shown when the trial has expired and no active
/// subscription is present. Also presentable as a sheet from the trial
/// banner for users who want to upgrade early.
struct PaywallView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// When true, the view is being shown as a sheet and should render a
    /// dismiss button instead of a sign-out button.
    var presentedAsSheet: Bool = false

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                header
                planCards
                errorView
                restoreRow
                legalRow
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 40)
            .padding(.top, 50)

            // Corner action: dismiss (sheet) or sign out (full screen).
            VStack {
                HStack {
                    Spacer()
                    if presentedAsSheet {
                        Button("Close") { dismiss() }
                            .buttonStyle(.borderless)
                    } else {
                        Button("Sign Out", role: .destructive) {
                            Task { await appState.authService.signOut() }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding()
                Spacer()
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Unlock Poker HUD")
                .font(.largeTitle)
                .fontWeight(.bold)
            if let email = appState.authService.currentEmail {
                Text("Subscribing as \(email)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if case .trial(let remaining) = appState.subscriptionManager.entitlement, remaining > 0 {
                Text("You still have \(TrialBannerView.format(remaining: remaining)) of free trial left.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Your free trial has ended. Choose a plan to keep using Poker HUD.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var planCards: some View {
        HStack(spacing: 24) {
            if let monthly = appState.subscriptionManager.monthlyProduct {
                PlanCard(
                    product: monthly,
                    badge: nil,
                    isPurchasing: appState.subscriptionManager.isPurchasing,
                    onSubscribe: {
                        Task { await appState.subscriptionManager.purchase(monthly) }
                    }
                )
            } else {
                loadingCard
            }

            if let yearly = appState.subscriptionManager.yearlyProduct {
                PlanCard(
                    product: yearly,
                    badge: "Save 17%",
                    isPurchasing: appState.subscriptionManager.isPurchasing,
                    onSubscribe: {
                        Task { await appState.subscriptionManager.purchase(yearly) }
                    }
                )
            } else {
                loadingCard
            }
        }
    }

    private var loadingCard: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(NSColor.controlBackgroundColor))
            .frame(width: 240, height: 280)
            .overlay(ProgressView())
    }

    @ViewBuilder
    private var errorView: some View {
        if let error = appState.subscriptionManager.purchaseError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520)
        }
    }

    private var restoreRow: some View {
        Button("Restore purchases") {
            Task { await appState.subscriptionManager.restorePurchases() }
        }
        .buttonStyle(.link)
    }

    private var legalRow: some View {
        HStack(spacing: 24) {
            Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            Link("Privacy Policy", destination: URL(string: "https://github.com/matteocaglio1989-cmd/Poker-HUD/blob/main/PRIVACY.md")!)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
