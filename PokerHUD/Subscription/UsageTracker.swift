import Foundation
import AppKit
import Combine

/// Accumulates wall-clock seconds of active app usage while the user is
/// on the free trial, and periodically flushes the delta to Supabase via
/// `SubscriptionRepository.addUsageSeconds`.
///
/// Counting only happens while:
///   - the user is authenticated (the owner of the tracker starts it from
///     `AppState.onAuthenticated()`),
///   - the current entitlement is `.trial`,
///   - and the app is the frontmost application (foreground).
///
/// When the entitlement flips to `.active` or `.expired`, or the user signs
/// out, `stop()` is called and the ticker is suspended.
@MainActor
final class UsageTracker {
    private let repo: SubscriptionRepository
    private weak var subscriptionManager: SubscriptionManager?

    private var timer: Timer?
    private var pendingSeconds: Int = 0
    private var isForeground: Bool
    private var isRunning: Bool = false

    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var entitlementCancellable: AnyCancellable?

    init(
        subscriptionManager: SubscriptionManager,
        repo: SubscriptionRepository = SubscriptionRepository()
    ) {
        self.repo = repo
        self.subscriptionManager = subscriptionManager
        self.isForeground = NSApplication.shared.isActive
    }

    deinit {
        if let f = foregroundObserver { NotificationCenter.default.removeObserver(f) }
        if let b = backgroundObserver { NotificationCenter.default.removeObserver(b) }
        timer?.invalidate()
    }

    // MARK: - Public API

    /// Begin tracking. Idempotent: safe to call from the auth change callback
    /// even if already running.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.isForeground = true; self?.startTimerIfNeeded() }
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.isForeground = false; self?.stopTimer() }
        }

        // React to entitlement changes: if the user purchases or the trial
        // runs out we should stop accruing seconds.
        entitlementCancellable = subscriptionManager?.$entitlement
            .sink { [weak self] entitlement in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if entitlement.isTrial {
                        self.startTimerIfNeeded()
                    } else {
                        self.stopTimer()
                        // Flush any remaining seconds so the counter is accurate
                        // if the user later downgrades / re-enters the trial.
                        await self.flushPending()
                    }
                }
            }

        startTimerIfNeeded()
    }

    /// Stop tracking entirely and flush any buffered seconds.
    func stop() {
        isRunning = false
        stopTimer()
        if let f = foregroundObserver {
            NotificationCenter.default.removeObserver(f)
            foregroundObserver = nil
        }
        if let b = backgroundObserver {
            NotificationCenter.default.removeObserver(b)
            backgroundObserver = nil
        }
        entitlementCancellable?.cancel()
        entitlementCancellable = nil
        Task { @MainActor [weak self] in await self?.flushPending() }
    }

    // MARK: - Internal ticking

    private func startTimerIfNeeded() {
        guard isRunning,
              isForeground,
              subscriptionManager?.entitlement.isTrial == true,
              timer == nil else { return }

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        pendingSeconds += 1
        if TimeInterval(pendingSeconds) >= TrialPolicy.flushIntervalSeconds {
            Task { @MainActor [weak self] in await self?.flushPending() }
        }
    }

    private func flushPending() async {
        guard pendingSeconds > 0 else { return }
        let delta = pendingSeconds
        pendingSeconds = 0
        do {
            _ = try await repo.addUsageSeconds(delta)
        } catch {
            // On failure, roll back so we don't lose the seconds — they'll
            // be retried on the next flush.
            pendingSeconds += delta
            print("[UsageTracker] addUsageSeconds failed: \(error)")
            return
        }
        // Refresh entitlement so the countdown UI updates and the paywall
        // appears the moment the trial hits zero.
        await subscriptionManager?.refreshEntitlement()
    }
}
