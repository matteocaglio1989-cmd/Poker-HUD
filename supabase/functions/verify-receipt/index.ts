// POST /verify-receipt
//
// Invoked by the Poker HUD macOS app after a successful StoreKit 2 purchase
// or when resolving Transaction.currentEntitlements at launch. Body:
//
//   { "jwsRepresentation": "<signed transaction JWS>" }
//
// Flow:
//   1. Authenticate the caller via their Supabase JWT.
//   2. Verify the JWS using Apple's public keys (apple-jws.ts helper).
//   3. Upsert the decoded transaction into public.subscriptions using the
//      service_role key (bypasses RLS).
//   4. Return the stored row to the client.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
    verifyAppleJWS,
    planForProductId,
    statusForExpiry,
    type SignedTransactionInfo,
} from "../_shared/apple-jws.ts";

interface RequestBody {
    jwsRepresentation?: string;
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function jsonResponse(body: unknown, status = 200): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json" },
    });
}

Deno.serve(async (req) => {
    if (req.method !== "POST") {
        return jsonResponse({ error: "method not allowed" }, 405);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
        return jsonResponse({ error: "missing bearer token" }, 401);
    }

    // Resolve the caller's user id from their JWT.
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) {
        return jsonResponse({ error: "invalid token" }, 401);
    }
    const userId = userData.user.id;

    let body: RequestBody;
    try {
        body = await req.json();
    } catch {
        return jsonResponse({ error: "invalid json body" }, 400);
    }
    if (!body.jwsRepresentation) {
        return jsonResponse({ error: "jwsRepresentation required" }, 400);
    }

    let tx: SignedTransactionInfo;
    try {
        tx = await verifyAppleJWS<SignedTransactionInfo>(body.jwsRepresentation);
    } catch (err) {
        console.error("JWS verification failed:", err);
        return jsonResponse({ error: "invalid signed transaction" }, 400);
    }

    let plan: "monthly" | "yearly";
    try {
        plan = planForProductId(tx.productId);
    } catch (err) {
        console.error(err);
        return jsonResponse({ error: "unknown product id" }, 400);
    }

    const status = statusForExpiry(tx.expiresDate);
    const environment = tx.environment === "Production" ? "production" : "sandbox";

    const row = {
        user_id: userId,
        product_id: tx.productId,
        plan,
        status,
        original_transaction_id: tx.originalTransactionId,
        latest_transaction_id: tx.transactionId,
        current_period_start: new Date(tx.purchaseDate).toISOString(),
        current_period_end: new Date(tx.expiresDate ?? Date.now()).toISOString(),
        auto_renew: true,
        environment,
        updated_at: new Date().toISOString(),
    };

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { data, error } = await admin
        .from("subscriptions")
        .upsert(row, { onConflict: "user_id" })
        .select()
        .single();

    if (error) {
        console.error("upsert failed:", error);
        return jsonResponse({ error: "db error" }, 500);
    }

    return jsonResponse({ subscription: data });
});
