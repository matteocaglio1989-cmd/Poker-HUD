import Foundation

/// Supported subscription cadences. Mirrors the `plan` column in
/// `public.subscriptions` on Supabase.
enum Plan: String, Codable {
    case monthly
    case yearly

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly:  return "Yearly"
        }
    }
}

/// Resolved access level for the current user. Computed fresh by
/// `SubscriptionManager.refreshEntitlement()` whenever Supabase, StoreKit,
/// or the trial counter changes.
enum Entitlement: Equatable {
    /// Not yet loaded — show a spinner, never flash the paywall.
    case unknown
    /// User still has trial seconds left.
    case trial(remainingSeconds: TimeInterval)
    /// Paid subscription is currently active and not expired.
    case active(plan: Plan, expiresAt: Date)
    /// Trial burnt out and no active subscription.
    case expired

    /// Whether the main app UI should be shown.
    var grantsAccess: Bool {
        switch self {
        case .trial(let remaining): return remaining > 0
        case .active:               return true
        case .unknown, .expired:    return false
        }
    }

    var isTrial: Bool {
        if case .trial = self { return true }
        return false
    }
}

/// Shape of a row in `public.subscriptions`, decoded from PostgREST.
struct SubscriptionRecord: Codable, Equatable {
    let productId: String
    let plan: Plan
    let status: String
    let currentPeriodEnd: Date
    let autoRenew: Bool

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case plan
        case status
        case currentPeriodEnd = "current_period_end"
        case autoRenew = "auto_renew"
    }

    var isActive: Bool {
        status == "active" && currentPeriodEnd > Date()
    }
}

/// App Store Connect product identifiers. Must match the auto-renewable
/// subscriptions configured in App Store Connect.
enum SubscriptionProductIDs {
    static let monthly = "com.pokerhud.app.subscription.monthly"
    static let yearly  = "com.pokerhud.app.subscription.yearly"
    static let all: [String] = [monthly, yearly]

    static func plan(for productId: String) -> Plan? {
        switch productId {
        case monthly: return .monthly
        case yearly:  return .yearly
        default:      return nil
        }
    }
}

/// Policy constants for the custom, Supabase-tracked free trial. We can't
/// use StoreKit's native introductory offer because Apple's minimum free
/// trial is 3 days, and the product requirement is 3 hours of cumulative
/// active usage.
enum TrialPolicy {
    /// 3 hours, expressed in seconds.
    static let totalSeconds: TimeInterval = 3 * 60 * 60

    /// How often (in seconds of accumulated use) the client flushes its
    /// in-memory counter to Supabase. Lower values are more accurate at the
    /// cost of more writes.
    static let flushIntervalSeconds: TimeInterval = 30
}
