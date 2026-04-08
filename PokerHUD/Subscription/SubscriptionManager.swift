import Foundation
import StoreKit
import AppKit

/// Drives StoreKit 2 purchases and resolves the user's current entitlement
/// against both StoreKit and the Supabase `subscriptions` table.
///
/// Resolution priority inside `refreshEntitlement()`:
///   1. Supabase row with `status == active` and unexpired period.
///   2. StoreKit's local `Transaction.currentEntitlements` — if a valid
///      transaction exists locally but the server hasn't caught up yet,
///      upload its JWS to the `verify-receipt` edge function, then re-read.
///   3. Cumulative trial seconds from the `user_usage` table.
///
/// This keeps Supabase as the source of truth (so gating survives on machines
/// that haven't seen a StoreKit event yet, e.g. after a cold install), while
/// still honouring fresh purchases before the server-to-server notification
/// lands.
@MainActor
final class SubscriptionManager: ObservableObject {
    @Published private(set) var entitlement: Entitlement = .unknown
    @Published private(set) var products: [Product] = []
    @Published private(set) var isPurchasing: Bool = false
    @Published var purchaseError: String?
    /// Set whenever `loadProducts()` fails (or returns no products), so the
    /// paywall can show an error + Retry instead of spinning forever. Cleared
    /// at the start of every `loadProducts()` call. This was added because
    /// silently swallowing the error to a `print` left the paywall stuck on
    /// two `ProgressView`s when the StoreKit configuration file wasn't
    /// selected in the active Xcode scheme — exactly the dev trap we hit.
    @Published var loadProductsError: String?

    private let repo: SubscriptionRepository
    private var transactionListener: Task<Void, Never>?

    init(repo: SubscriptionRepository = SubscriptionRepository()) {
        self.repo = repo
        startTransactionListener()
    }

    deinit {
        transactionListener?.cancel()
    }

    var monthlyProduct: Product? {
        products.first { $0.id == SubscriptionProductIDs.monthly }
    }

    var yearlyProduct: Product? {
        products.first { $0.id == SubscriptionProductIDs.yearly }
    }

    // MARK: - Lifecycle

    /// Load StoreKit products into `products`. Safe to call repeatedly —
    /// the paywall's Retry button calls this directly.
    func loadProducts() async {
        loadProductsError = nil
        do {
            let loaded = try await Product.products(for: SubscriptionProductIDs.all)
            self.products = loaded.sorted { $0.price < $1.price }
            if loaded.isEmpty {
                // StoreKit returned an empty result without throwing — most
                // commonly because the Xcode scheme isn't pointing at the
                // .storekit configuration file and there's no sandbox tester
                // signed in either.
                self.loadProductsError = "No subscription plans returned by StoreKit."
            }
        } catch {
            print("[SubscriptionManager] loadProducts failed: \(error)")
            // The bare `error.localizedDescription` for StoreKit/ASD errors is
            // almost always something useless like "Unable to Complete Request",
            // which leaves us guessing at the actual root cause. Bridge to
            // NSError and include the domain + code + full Swift description
            // so the paywall card surfaces enough detail to pinpoint things
            // like ASDErrorDomain 509 (team-id mismatch) vs 825 (no products).
            let ns = error as NSError
            self.loadProductsError = """
                \(error.localizedDescription)

                [\(ns.domain) \(ns.code)] \(String(describing: error))
                """
        }
    }

    #if DEBUG
    /// UserDefaults key used to persist a dev-only paywall bypass across
    /// relaunches. Set by `devGrantSubscription(days:)` and consulted at the
    /// top of `refreshEntitlement()`. Stripped from release builds by the
    /// compile-time `#if DEBUG` gate.
    private static let devBypassUntilDateKey = "dev.subscription.bypass.untilDate"
    #endif

    /// Recompute `entitlement` from Supabase + StoreKit + trial usage.
    func refreshEntitlement() async {
        #if DEBUG
        // Dev-only bypass: if a debug developer has clicked "Dev: Grant 30-day
        // test subscription" on the paywall's error card, short-circuit to
        // `.active` until that stored date passes. Lets the app be used
        // end-to-end without fighting Xcode's SPM-executable StoreKit Testing
        // harness activation. Guarded by #if DEBUG so it's never compiled
        // into release builds.
        if let until = UserDefaults.standard.object(forKey: Self.devBypassUntilDateKey) as? Date,
           until > Date() {
            self.entitlement = .active(plan: .monthly, expiresAt: until)
            return
        }
        #endif

        // Step 1: Supabase source of truth.
        if let record = try? await repo.fetchSubscription(), record.isActive,
           let plan = SubscriptionProductIDs.plan(for: record.productId) {
            self.entitlement = .active(plan: plan, expiresAt: record.currentPeriodEnd)
            return
        }

        // Step 2: Reconcile with StoreKit's local entitlements.
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result else { continue }
            guard SubscriptionProductIDs.all.contains(tx.productID) else { continue }
            if let expires = tx.expirationDate, expires <= Date() { continue }

            // Upload the JWS so the server row catches up.
            // `jwsRepresentation` lives on `VerificationResult`, not on the
            // unwrapped `Transaction` itself — we read it from `result`.
            _ = try? await repo.verifyReceipt(jws: result.jwsRepresentation)

            // Re-read the now-updated row.
            if let record = try? await repo.fetchSubscription(), record.isActive,
               let plan = SubscriptionProductIDs.plan(for: record.productId) {
                self.entitlement = .active(plan: plan, expiresAt: record.currentPeriodEnd)
                return
            }

            // Fallback: trust the local transaction until the server catches up.
            if let plan = SubscriptionProductIDs.plan(for: tx.productID) {
                self.entitlement = .active(plan: plan, expiresAt: tx.expirationDate ?? Date().addingTimeInterval(60 * 60 * 24 * 30))
                return
            }
        }

        // Step 3: Fall back to the custom trial counter. The trial is
        // 100 imported hands (migration 0002) — see TrialPolicy.
        do {
            let usage = try await repo.fetchUsage()
            let remaining = TrialPolicy.totalHands - usage.handsImported
            self.entitlement = remaining > 0 ? .trial(remainingHands: remaining) : .expired
        } catch {
            print("[SubscriptionManager] fetchUsage failed: \(error)")
            // Fail closed: don't silently grant access if we can't read usage.
            self.entitlement = .expired
        }
    }

    /// Reset in-memory state on sign-out so the next user starts clean.
    func reset() {
        entitlement = .unknown
        purchaseError = nil
        isPurchasing = false
    }

    #if DEBUG
    /// Dev-only override: grants a synthetic `.active` entitlement for
    /// `days` days and persists the expiry to `UserDefaults` so the bypass
    /// survives app relaunches. Exposed on the paywall's error card via a
    /// `#if DEBUG`-gated button so developers can exercise the post-purchase
    /// code paths without having to first solve Xcode's SPM-executable
    /// StoreKit Testing harness activation (which won't reliably load the
    /// local .storekit file in this project layout).
    ///
    /// Release builds strip this method entirely via the `#if DEBUG` gate —
    /// there is no way to call it from a production binary.
    func devGrantSubscription(days: Int = 30) {
        let until = Date().addingTimeInterval(TimeInterval(days) * 86_400)
        UserDefaults.standard.set(until, forKey: Self.devBypassUntilDateKey)
        self.entitlement = .active(plan: .monthly, expiresAt: until)
        print("[SubscriptionManager] DEV bypass active until \(until)")
    }
    #endif

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        purchaseError = nil
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let tx):
                    _ = try? await repo.verifyReceipt(jws: verification.jwsRepresentation)
                    await tx.finish()
                    await refreshEntitlement()
                case .unverified(_, let error):
                    self.purchaseError = "Could not verify purchase: \(error.localizedDescription)"
                }
            case .userCancelled:
                break
            case .pending:
                self.purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            self.purchaseError = error.localizedDescription
        }
    }

    /// Restore purchases: syncs local StoreKit state with the App Store and
    /// re-resolves entitlement.
    func restorePurchases() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
        } catch {
            self.purchaseError = error.localizedDescription
        }
        await refreshEntitlement()
    }

    /// Open Apple's subscription management page. On macOS,
    /// `AppStore.showManageSubscriptions(in:)` is iOS-only, so we open the
    /// canonical URL in the user's default browser, which the system then
    /// hands off to the App Store app.
    func openManageSubscriptions() {
        let url = URL(string: "https://apps.apple.com/account/subscriptions")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Transaction listener

    /// Listen for background transaction updates (renewals, refunds, upgrades
    /// from other devices). Each verified update is pushed through the
    /// verify-receipt edge function so Supabase stays in sync, then we
    /// refresh the entitlement.
    private func startTransactionListener() {
        transactionListener = Task(priority: .background) { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let tx) = update,
                   SubscriptionProductIDs.all.contains(tx.productID) {
                    _ = try? await self.repo.verifyReceipt(jws: update.jwsRepresentation)
                    await tx.finish()
                    await self.refreshEntitlement()
                }
            }
        }
    }
}

