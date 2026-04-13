import Foundation
import Supabase

/// Thin wrapper around the Supabase client for subscription and trial-usage
/// persistence. All methods assume the caller is already authenticated — if
/// the JWT is missing/expired Supabase will return an error that propagates.
@MainActor
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

    struct UsageRow: Codable {
        let totalTrialSeconds: Int
        let trialStartedAt: Date

        enum CodingKeys: String, CodingKey {
            case totalTrialSeconds = "total_trial_seconds"
            case trialStartedAt    = "trial_started_at"
        }
    }

    /// Fetch the cumulative trial seconds for the current user, creating the
    /// row on first call.
    func fetchUsage() async throws -> UsageRow {
        if let existing: UsageRow = try? await client
            .from("user_usage")
            .select("total_trial_seconds, trial_started_at")
            .single()
            .execute()
            .value {
            return existing
        }

        // First call for this user — insert a default row. We rely on RLS to
        // key the insert on auth.uid(); the DB defaults fill in the rest.
        struct InsertRow: Encodable { let total_trial_seconds: Int }
        let inserted: UsageRow = try await client
            .from("user_usage")
            .insert(InsertRow(total_trial_seconds: 0))
            .select("total_trial_seconds, trial_started_at")
            .single()
            .execute()
            .value
        return inserted
    }

    /// Atomically increment the current user's trial counter by `delta`
    /// seconds via the `add_usage_seconds` SECURITY DEFINER RPC.
    func addUsageSeconds(_ delta: Int) async throws -> UsageRow {
        struct Params: Encodable { let delta: Int }
        let updated: UsageRow = try await client
            .rpc("add_usage_seconds", params: Params(delta: delta))
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
