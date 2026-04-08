import Foundation

/// Flushes freshly-imported hand counts to Supabase while the user is on
/// the custom free trial, then asks `SubscriptionManager` to re-resolve
/// the entitlement so the UI updates (and the paywall appears the moment
/// the counter hits the 100-hand cap in `TrialPolicy.totalHands`).
///
/// The old implementation accumulated wall-clock seconds from a 1 Hz
/// timer; that was replaced by the 100-hand policy (migration 0002) and
/// the tracker is now entirely event-driven — it only fires when
/// `AppState` reports a successful import. Start/stop no longer manage
/// any resources, but they're kept as no-ops so the AppState auth
/// lifecycle hooks don't need to change shape.
@MainActor
final class UsageTracker {
    private let repo: SubscriptionRepository
    private weak var subscriptionManager: SubscriptionManager?

    init(
        subscriptionManager: SubscriptionManager,
        repo: SubscriptionRepository = SubscriptionRepository()
    ) {
        self.repo = repo
        self.subscriptionManager = subscriptionManager
    }

    // MARK: - Public API

    /// Kept for call-site compatibility with the old timer-based
    /// tracker. No resources to allocate any more.
    func start() {}

    /// Kept for call-site compatibility with the old timer-based
    /// tracker. No resources to release any more.
    func stop() {}

    /// Record that `count` new hands were just imported. Only has an
    /// effect while the current entitlement is `.trial` — if the user
    /// is already on an active subscription or the trial has expired,
    /// this is a no-op so we don't burn RPC quota or confuse the UI.
    ///
    /// After the RPC succeeds, asks `SubscriptionManager` to refresh
    /// the entitlement so the banner countdown updates live and the
    /// paywall appears the moment the counter reaches the 100-hand cap.
    func recordHandsImported(_ count: Int) {
        guard count > 0 else { return }
        guard subscriptionManager?.entitlement.isTrial == true else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.repo.addImportedHands(count)
            } catch {
                print("[UsageTracker] addImportedHands failed: \(error)")
                return
            }
            await self.subscriptionManager?.refreshEntitlement()
        }
    }
}
