// POST /delete-account
//
// Permanently deletes the authenticated user's account and all associated
// data. Called from the macOS app when the user taps "Delete Account" in
// Settings. Required by App Store guideline 5.1.1(v).
//
// Flow:
//   1. Authenticate the caller via their Supabase JWT.
//   2. Delete rows from public.subscriptions and public.user_usage
//      (service_role bypasses RLS).
//   3. Delete the user from auth.users via the admin API.
//   4. Return { ok: true }.
//
// The edge function runs with the service_role key, so any auth.users
// row referenced by the caller's JWT can be removed. We do NOT allow
// cross-user deletion — the `user_id` is always pulled from the JWT,
// never from the request body.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

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

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // 1. Remove subscription row (service_role bypasses RLS).
    const { error: subErr } = await admin
        .from("subscriptions")
        .delete()
        .eq("user_id", userId);
    if (subErr) {
        console.error("subscriptions delete failed:", subErr);
        return jsonResponse({ error: "db error (subscriptions)" }, 500);
    }

    // 2. Remove usage row.
    const { error: usageErr } = await admin
        .from("user_usage")
        .delete()
        .eq("user_id", userId);
    if (usageErr) {
        console.error("user_usage delete failed:", usageErr);
        return jsonResponse({ error: "db error (user_usage)" }, 500);
    }

    // 3. Delete the auth user. This cascades to auth.identities and any
    //    remaining auth.* rows.
    const { error: deleteErr } = await admin.auth.admin.deleteUser(userId);
    if (deleteErr) {
        console.error("auth.users delete failed:", deleteErr);
        return jsonResponse({ error: "auth delete failed" }, 500);
    }

    return jsonResponse({ ok: true });
});
