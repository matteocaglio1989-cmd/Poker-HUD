// POST /app-store-notifications
//
// Webhook endpoint for App Store Server Notifications V2. Configure the
// production + sandbox URLs for this function in App Store Connect under
// App Information > App Store Server Notifications.
//
// Apple POSTs a JSON body containing a single `signedPayload` JWS. We verify
// it, then walk into the nested `signedTransactionInfo` / `signedRenewalInfo`
// JWS blobs to extract the per-transaction state. Finally we upsert the
// matching row in public.subscriptions (keyed by original_transaction_id)
// using the service_role key.
//
// Reference: https://developer.apple.com/documentation/appstoreservernotifications

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
    verifyAppleJWS,
    planForProductId,
    statusForExpiry,
    type NotificationPayload,
    type SignedTransactionInfo,
    type SignedRenewalInfo,
} from "../_shared/apple-jws.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function jsonResponse(body: unknown, status = 200): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json" },
    });
}

/// Map an App Store notification type + subtype to our internal status column.
function statusFor(
    notificationType: string,
    subtype: string | undefined,
    expiresDate: number | undefined,
): string {
    switch (notificationType) {
        case "SUBSCRIBED":
        case "DID_RENEW":
        case "OFFER_REDEEMED":
            return statusForExpiry(expiresDate);
        case "GRACE_PERIOD_EXPIRED":
            return "expired";
        case "EXPIRED":
            return "expired";
        case "REFUND":
        case "REVOKE":
            return "revoked";
        case "DID_CHANGE_RENEWAL_STATUS":
            return subtype === "AUTO_RENEW_DISABLED"
                ? statusForExpiry(expiresDate)
                : statusForExpiry(expiresDate);
        case "DID_FAIL_TO_RENEW":
            return subtype === "GRACE_PERIOD" ? "in_grace" : "expired";
        default:
            return statusForExpiry(expiresDate);
    }
}

Deno.serve(async (req) => {
    if (req.method !== "POST") {
        return jsonResponse({ error: "method not allowed" }, 405);
    }

    let body: { signedPayload?: string };
    try {
        body = await req.json();
    } catch {
        return jsonResponse({ error: "invalid json" }, 400);
    }
    if (!body.signedPayload) {
        return jsonResponse({ error: "signedPayload required" }, 400);
    }

    let notification: NotificationPayload;
    try {
        notification = await verifyAppleJWS<NotificationPayload>(body.signedPayload);
    } catch (err) {
        console.error("signedPayload verification failed:", err);
        return jsonResponse({ error: "invalid signedPayload" }, 400);
    }

    const signedTx = notification.data.signedTransactionInfo;
    if (!signedTx) {
        // Some notification types (e.g. CONSUMPTION_REQUEST) carry no tx data —
        // ack them and move on.
        return jsonResponse({ ok: true, ignored: notification.notificationType });
    }

    let tx: SignedTransactionInfo;
    try {
        tx = await verifyAppleJWS<SignedTransactionInfo>(signedTx);
    } catch (err) {
        console.error("signedTransactionInfo verification failed:", err);
        return jsonResponse({ error: "invalid signedTransactionInfo" }, 400);
    }

    let renewal: SignedRenewalInfo | undefined;
    if (notification.data.signedRenewalInfo) {
        try {
            renewal = await verifyAppleJWS<SignedRenewalInfo>(
                notification.data.signedRenewalInfo,
            );
        } catch (err) {
            console.error("signedRenewalInfo verification failed:", err);
        }
    }

    let plan: "monthly" | "yearly";
    try {
        plan = planForProductId(tx.productId);
    } catch (err) {
        console.error(err);
        return jsonResponse({ error: "unknown product id" }, 400);
    }

    const status = statusFor(notification.notificationType, notification.subtype, tx.expiresDate);
    const environment = tx.environment === "Production" ? "production" : "sandbox";

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // Find the matching user via original_transaction_id. The row was created
    // by verify-receipt when the user first purchased, so it must already
    // exist for us to attribute the notification.
    const { data: existing, error: lookupErr } = await admin
        .from("subscriptions")
        .select("user_id")
        .eq("original_transaction_id", tx.originalTransactionId)
        .maybeSingle();

    if (lookupErr) {
        console.error("lookup failed:", lookupErr);
        return jsonResponse({ error: "db error" }, 500);
    }
    if (!existing) {
        // Unknown transaction — likely arrived before the client called
        // verify-receipt, or for a user we've never seen. Ack so Apple stops
        // retrying; we'll reconcile next time the user opens the app.
        return jsonResponse({ ok: true, ignored: "unknown original_transaction_id" });
    }

    const { error: updateErr } = await admin
        .from("subscriptions")
        .update({
            product_id: tx.productId,
            plan,
            status,
            latest_transaction_id: tx.transactionId,
            current_period_start: new Date(tx.purchaseDate).toISOString(),
            current_period_end: new Date(tx.expiresDate ?? Date.now()).toISOString(),
            auto_renew: renewal ? renewal.autoRenewStatus === 1 : true,
            environment,
            updated_at: new Date().toISOString(),
        })
        .eq("user_id", existing.user_id);

    if (updateErr) {
        console.error("update failed:", updateErr);
        return jsonResponse({ error: "db error" }, 500);
    }

    return jsonResponse({ ok: true, notificationType: notification.notificationType });
});
