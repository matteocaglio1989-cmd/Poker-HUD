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
                Text("You still have \(TrialBannerView.format(remainingHands: remaining)) left on your free trial.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Your free trial has ended. Choose a plan to keep using Poker HUD.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var planCards: some View {
        // If StoreKit failed (or returned no products) AND we have nothing to
        // show, surface an actionable error card instead of two indefinite
        // spinners. The paywall used to silently spin forever when the Xcode
        // scheme wasn't pointing at MacOSPokerHud.storekit — see SubscriptionManager
        // .loadProducts() for the now-published `loadProductsError`.
        if appState.subscriptionManager.products.isEmpty,
           let error = appState.subscriptionManager.loadProductsError {
            loadFailedCard(error: error)
        } else {
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
    }

    private var loadingCard: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(NSColor.controlBackgroundColor))
            .frame(width: 240, height: 280)
            .overlay(ProgressView())
    }

    /// Single full-width error card shown when StoreKit cannot return any
    /// products. Includes a Retry button that re-runs `loadProducts()` and a
    /// dev hint that points at the most common cause (the .storekit scheme
    /// configuration file not being selected in Xcode).
    private func loadFailedCard(error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Couldn't load subscription plans")
                .font(.headline)
            Text(error)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tip: in Xcode go to Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration and select MacOSPokerHud.storekit, then relaunch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Button {
                Task { await appState.subscriptionManager.loadProducts() }
            } label: {
                Text("Retry")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)

            #if DEBUG
            // Dev-only escape hatch: Xcode's StoreKit Testing harness
            // doesn't reliably activate for SPM executable targets, so
            // Product.products(for:) keeps failing with networkError in
            // our dev setup. This button lets developers bypass the
            // paywall and exercise the post-purchase flows anyway. The
            // bypass is persisted across relaunches via UserDefaults.
            // Compiled out of release builds entirely.
            Button {
                appState.subscriptionManager.devGrantSubscription(days: 30)
            } label: {
                Text("Dev: Grant 30-day test subscription")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.top, 2)
            #endif
        }
        .padding(24)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
        )
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
            Link("Privacy Policy", destination: URL(string: "https://github.com/matteocaglio1989-cmd/Poker-HUD#privacy")!)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
