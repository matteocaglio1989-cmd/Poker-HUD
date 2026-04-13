import Foundation

/// Tracks imported-hand counts for the free trial. Uses a LOCAL
/// UserDefaults counter as the primary mechanism (reliable, no
/// network dependency) and optionally syncs to Supabase as a
/// secondary record.
///
/// The old implementation relied entirely on a Supabase RPC
/// (`add_imported_hands`) which silently failed when the migration
/// wasn't applied, leaving the trial counter stuck at 100 forever.
/// The local counter fixes this: every successful import increments
/// a UserDefaults integer, and `SubscriptionManager.refreshEntitlement`
/// reads it directly — no network round-trip needed.
@MainActor
final class UsageTracker {
    private let repo: SubscriptionRepository
    private weak var subscriptionManager: SubscriptionManager?

    /// UserDefaults key for the local imported-hands counter.
    private static let localHandsKey = "trial.handsImported"

    init(
        subscriptionManager: SubscriptionManager,
        repo: SubscriptionRepository = SubscriptionRepository()
    ) {
        self.repo = repo
        self.subscriptionManager = subscriptionManager
    }

    // MARK: - Public API

    func start() {}
    func stop() {}

    /// Record that `count` new hands were just imported.
    ///
    /// Always increments the local UserDefaults counter (regardless
    /// of entitlement state — even if the user is subscribed, we
    /// track in case they cancel later). Then refreshes the
    /// entitlement so the sidebar banner updates live.
    func recordHandsImported(_ count: Int) {
        guard count > 0 else { return }

        // Always increment the local counter — it's the source of
        // truth for the trial. Cheap, no network, no failure mode.
        let current = UserDefaults.standard.integer(forKey: Self.localHandsKey)
        UserDefaults.standard.set(current + count, forKey: Self.localHandsKey)

        // Only refresh entitlement if on trial (avoid unnecessary
        // Supabase calls for subscribers).
        guard subscriptionManager?.entitlement.isTrial == true else { return }

        // Best-effort sync to Supabase (for multi-device tracking).
        // If it fails, the local counter is still correct.
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.repo.addImportedHands(count)
            } catch {
                Log.subscription.error("addImportedHands (Supabase) failed: \(error.localizedDescription, privacy: .public) — local counter is still accurate")
            }
            await self.subscriptionManager?.refreshEntitlement()
        }
    }

    /// Read the local imported-hands count. Used by
    /// `SubscriptionManager.refreshEntitlement` as the primary
    /// source of truth for the trial counter.
    static var localHandsImported: Int {
        UserDefaults.standard.integer(forKey: localHandsKey)
    }
}
