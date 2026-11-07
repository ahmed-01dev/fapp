import { createClient } from "npm:@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5.9.6";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), {
  status, headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
});
type ServiceAccount = { client_email: string; private_key: string; project_id: string; token_uri?: string };

async function getFcmAccessToken(account: ServiceAccount): Promise<string> {
  const tokenUri = account.token_uri ?? "https://oauth2.googleapis.com/token";
  const key = await importPKCS8(account.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  }).setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email).setSubject(account.client_email)
    .setAudience(tokenUri).setIssuedAt(now).setExpirationTime(now + 3600).sign(key);
  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!response.ok) throw new Error("fcm_oauth_failed");
  const result = await response.json();
  if (typeof result.access_token !== "string") throw new Error("fcm_oauth_missing_token");
  return result.access_token;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json({ error: "authentication_required" }, 401);
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceRoleKey) return json({ error: "server_not_configured" }, 500);

  const token = authorization.slice("Bearer ".length);
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "invalid_session" }, 401);

  let body: { call_id?: unknown };
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
  if (typeof body.call_id !== "string" || body.call_id.length > 64) return json({ error: "call_id_required" }, 400);

  const admin = createClient(url, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: call, error: callError } = await admin.from("call_sessions")
    .select("id,conversation_id,caller_id,callee_id,call_type,status")
    .eq("id", body.call_id).maybeSingle();
  if (callError || !call || call.caller_id !== authData.user.id) return json({ error: "call_not_found_or_not_owned" }, 404);
  if (call.status !== "ringing") return json({ sent: 0, skipped: 1, reason: "call_not_ringing" });

  const { data: blocks, error: blockError } = await admin.from("user_blocks")
    .select("blocker_id,blocked_id")
    .or(`and(blocker_id.eq.${call.caller_id},blocked_id.eq.${call.callee_id}),and(blocker_id.eq.${call.callee_id},blocked_id.eq.${call.caller_id})`);
  if (blockError) return json({ error: "privacy_check_failed" }, 500);
  if (blocks?.length) return json({ sent: 0, skipped: 1, reason: "blocked" });

  const { data: devices, error: deviceError } = await admin.from("device_push_tokens")
    .select("id,token,platform").eq("user_id", call.callee_id).is("disabled_at", null);
  if (deviceError) return json({ error: "device_lookup_failed" }, 500);
  if (!devices?.length) return json({ sent: 0, skipped: 1, reason: "no_registered_device" });

  const rawAccount = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!rawAccount) return json({ error: "push_provider_not_configured", sent: 0 }, 503);
  let account: ServiceAccount;
  try { account = JSON.parse(rawAccount); } catch { return json({ error: "invalid_fcm_service_account" }, 500); }
  if (!account.client_email || !account.private_key || !account.project_id) return json({ error: "invalid_fcm_service_account" }, 500);

  try {
    const accessToken = await getFcmAccessToken(account);
    let sent = 0;
    let failed = 0;
    for (const device of devices) {
      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: device.token,
            notification: {
              title: "مكالمة واردة على واصل",
              body: call.call_type === "video" ? "مكالمة فيديو واردة" : "مكالمة صوتية واردة",
            },
            data: {
              type: "incoming_call", call_id: call.id, conversation_id: call.conversation_id,
              caller_id: call.caller_id, call_type: call.call_type,
            },
            android: { priority: "high", ttl: "30s", notification: { channel_id: "wasel_calls", sound: "default" } },
            apns: { headers: { "apns-priority": "10", "apns-expiration": "30" } },
          },
        }),
      });
      if (response.ok) sent++;
      else {
        failed++;
        if (response.status === 404 || response.status === 400) {
          await admin.from("device_push_tokens").update({ disabled_at: new Date().toISOString() }).eq("id", device.id);
        }
      }
    }
    return json({ sent, failed, skipped: 0 });
  } catch {
    return json({ error: "push_delivery_failed" }, 502);
  }
});
