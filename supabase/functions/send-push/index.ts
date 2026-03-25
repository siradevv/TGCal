/**
 * Supabase Edge Function: send-push
 *
 * Receives a push notification request and delivers it via APNs (HTTP/2).
 * Called by database triggers via pg_net.
 *
 * Required Supabase secrets:
 *   APNS_KEY_ID        - Your APNs key ID (10-char, e.g. "ABC123DEFG")
 *   APNS_TEAM_ID       - Your Apple Developer Team ID
 *   APNS_PRIVATE_KEY   - The .p8 private key contents (PEM format)
 *   APNS_TOPIC          - Your app's bundle ID (e.g. "com.yourcompany.TGCal")
 *   APNS_ENVIRONMENT   - "production" or "development" (default: "production")
 *   SUPABASE_URL        - Auto-provided by Supabase
 *   SUPABASE_SERVICE_ROLE_KEY - Auto-provided by Supabase
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as jose from "https://deno.land/x/jose@v4.14.4/index.ts";

interface PushRequest {
  recipient_id: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

interface DeviceToken {
  token: string;
}

// ── Environment validation ──────────────────────────────

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value || value.trim().length === 0) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

// ── APNs JWT ──────────────────────────────────────────────

let cachedJwt: { token: string; expiresAt: number } | null = null;

async function getApnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  // Reuse JWT if still valid (APNs tokens last 1 hour, refresh at 50 min)
  if (cachedJwt && cachedJwt.expiresAt > now) {
    return cachedJwt.token;
  }

  const keyId = requireEnv("APNS_KEY_ID");
  const teamId = requireEnv("APNS_TEAM_ID");
  const privateKeyPem = requireEnv("APNS_PRIVATE_KEY");

  const privateKey = await jose.importPKCS8(privateKeyPem, "ES256");

  const jwt = await new jose.SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt(now)
    .setExpirationTime(now + 55 * 60)
    .sign(privateKey);

  cachedJwt = { token: jwt, expiresAt: now + 50 * 60 };
  return jwt;
}

// ── Send single push ─────────────────────────────────────

async function sendApnsPush(
  deviceToken: string,
  title: string,
  body: string,
  data: Record<string, unknown> = {},
): Promise<{ success: boolean; status: number; reason?: string }> {
  const environment = Deno.env.get("APNS_ENVIRONMENT") || "production";
  const topic = requireEnv("APNS_TOPIC");

  const host =
    environment === "production"
      ? "https://api.push.apple.com"
      : "https://api.sandbox.push.apple.com";

  const jwt = await getApnsJwt();

  // Nest user-provided data under a custom key to prevent overriding aps fields
  const payload = {
    aps: {
      alert: { title, body },
      sound: "default",
      badge: 1,
      "mutable-content": 1,
    },
    custom: data,
  };

  const response = await fetch(`${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      Authorization: `bearer ${jwt}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": "3600",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (response.ok) {
    return { success: true, status: response.status };
  }

  const errorBody = await response.json().catch(() => ({}));
  return {
    success: false,
    status: response.status,
    reason: errorBody?.reason || "Unknown",
  };
}

// ── Main handler ─────────────────────────────────────────

serve(async (req: Request) => {
  // Verify this is a POST with proper auth
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // Verify service role key (requests come from pg_net triggers)
  const authHeader = req.headers.get("Authorization") || "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceRoleKey || serviceRoleKey.trim().length === 0 || authHeader !== `Bearer ${serviceRoleKey}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  // Check that APNs is configured
  if (!Deno.env.get("APNS_KEY_ID") || !Deno.env.get("APNS_PRIVATE_KEY")) {
    console.warn("[send-push] APNs not configured, skipping");
    return new Response(
      JSON.stringify({ skipped: true, reason: "APNs not configured" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  let payload: PushRequest;
  try {
    payload = await req.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const { recipient_id, title, body, data } = payload;

  if (!recipient_id || !title || !body) {
    return new Response("Missing required fields", { status: 400 });
  }

  // Fetch device tokens for recipient
  const supabaseUrl = requireEnv("SUPABASE_URL");
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const { data: tokens, error } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("user_id", recipient_id);

  if (error) {
    console.error("[send-push] DB error:", error.message);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  if (!tokens || tokens.length === 0) {
    return new Response(
      JSON.stringify({ sent: 0, reason: "No device tokens" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  // Send to all registered devices
  const results = await Promise.all(
    (tokens as DeviceToken[]).map((t) => sendApnsPush(t.token, title, body, data || {})),
  );

  // Clean up invalid tokens (410 Gone = unregistered device)
  const invalidTokens = (tokens as DeviceToken[]).filter(
    (_, i) => results[i].status === 410 || results[i].reason === "BadDeviceToken",
  );

  if (invalidTokens.length > 0) {
    await supabase
      .from("device_tokens")
      .delete()
      .eq("user_id", recipient_id)
      .in(
        "token",
        invalidTokens.map((t) => t.token),
      );
    console.log(`[send-push] Cleaned ${invalidTokens.length} invalid tokens`);
  }

  const sent = results.filter((r) => r.success).length;
  const failed = results.filter((r) => !r.success);

  if (failed.length > 0) {
    console.warn("[send-push] Failed deliveries:", JSON.stringify(failed));
  }

  return new Response(
    JSON.stringify({ sent, failed: failed.length, total: tokens.length }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
