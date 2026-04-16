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
    /// User still has trial hands left. The counter ticks down one per
    /// successfully imported hand (not per wall-clock second — the old
    /// 3-hour model was replaced in migration 0002 because the
    /// wall-clock version ran down far slower than players expected).
    case trial(remainingHands: Int)
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
    static let monthly = "com.pokereye.pokerhud.pro.monthly"
    static let yearly  = "com.pokereye.pokerhud.pro.yearly"
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
/// trial is 3 days, and the product requirement is a fixed number of
/// imported hands. The old wall-clock "3 hours of cumulative active
/// usage" policy was replaced in migration 0002 because users reported
/// it ran down far too slowly in practice.
enum TrialPolicy {
    /// Hands a brand-new user can import before the paywall kicks in.
    static let totalHands: Int = 100
}
