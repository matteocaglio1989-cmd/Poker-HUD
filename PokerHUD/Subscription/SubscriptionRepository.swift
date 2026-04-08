import Foundation
import Supabase

/// Thin wrapper around the Supabase client for subscription and trial-usage
/// persistence. All methods assume the caller is already authenticated — if
/// the JWT is missing/expired Supabase will return an error that propagates.
///
/// Intentionally not `@MainActor`: every method is `async` and only touches
/// the Supabase client, which is itself thread-safe. Keeping the repo
/// nonisolated lets `SubscriptionManager` and `UsageTracker` use it as a
/// default initializer parameter (Swift 6 evaluates default parameter
/// expressions in a nonisolated context, so a `@MainActor` repo there
/// failed to compile).
struct SubscriptionRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    // MARK: - Subscription row

    /// Fetch the current user's subscription row, if any. Returns nil when
    /// no row exists (user has never purchased).
    func fetchSubscription() async throws -> SubscriptionRecord? {
        do {
            let record: SubscriptionRecord = try await client
                .from("subscriptions")
                .select("product_id, plan, status, current_period_end, auto_renew")
                .single()
                .execute()
                .value
            return record
        } catch {
            // PostgREST returns 406/PGRST116 for "no rows" from .single().
            // Treat that as "no subscription yet" rather than an error.
            let message = "\(error)".lowercased()
            if message.contains("pgrst116") || message.contains("no rows") {
                return nil
            }
            throw error
        }
    }

    // MARK: - Trial usage

    /// Shape of a row in `public.user_usage`. Both the legacy
    /// `total_trial_seconds` counter (3-hour wall-clock policy) and the
    /// new `hands_imported` counter (100-hand policy, migration 0002)
    /// are kept here so the client can tolerate a pre-migration DB
    /// during rollout. `handsImported` is the only field the trial
    /// entitlement reads today.
    struct UsageRow: Codable {
        let handsImported: Int
        let trialStartedAt: Date

        enum CodingKeys: String, CodingKey {
            case handsImported  = "hands_imported"
            case trialStartedAt = "trial_started_at"
        }
    }

    /// Fetch the cumulative imported-hand count for the current user,
    /// creating the row on first call. Selects `hands_imported` from
    /// the column added in migration 0002.
    func fetchUsage() async throws -> UsageRow {
        if let existing: UsageRow = try? await client
            .from("user_usage")
            .select("hands_imported, trial_started_at")
            .single()
            .execute()
            .value {
            return existing
        }

        // First call for this user — insert a default row. We rely on RLS to
        // key the insert on auth.uid(); the DB defaults fill in the rest.
        struct InsertRow: Encodable { let hands_imported: Int }
        let inserted: UsageRow = try await client
            .from("user_usage")
            .insert(InsertRow(hands_imported: 0))
            .select("hands_imported, trial_started_at")
            .single()
            .execute()
            .value
        return inserted
    }

    /// Atomically increment the current user's imported-hand counter
    /// by `delta` via the `add_imported_hands` SECURITY DEFINER RPC
    /// (migration 0002).
    func addImportedHands(_ delta: Int) async throws -> UsageRow {
        struct Params: Encodable { let delta: Int }
        let updated: UsageRow = try await client
            .rpc("add_imported_hands", params: Params(delta: delta))
            .single()
            .execute()
            .value
        return updated
    }

    // MARK: - Receipt verification

    struct VerifyResponse: Codable {
        let subscription: SubscriptionRecord
    }

    /// Post a StoreKit 2 JWS transaction to the verify-receipt edge function.
    /// Server upserts the subscription row using the service_role key and
    /// returns the stored row.
    func verifyReceipt(jws: String) async throws -> SubscriptionRecord {
        struct Body: Encodable { let jwsRepresentation: String }
        let response: VerifyResponse = try await client.functions
            .invoke(
                "verify-receipt",
                options: FunctionInvokeOptions(body: Body(jwsRepresentation: jws))
            )
        return response.subscription
    }
}
