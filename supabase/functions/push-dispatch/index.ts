import { createClient } from "npm:@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5.9.6";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
});

type ServiceAccount = { client_email: string; private_key: string; project_id: string; token_uri?: string };

async function fcmAccessToken(account: ServiceAccount): Promise<string> {
  const key = await importPKCS8(account.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  }).setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setSubject(account.client_email)
    .setAudience(account.token_uri ?? "https://oauth2.googleapis.com/token")
    .setIssuedAt(now).setExpirationTime(now + 3600).sign(key);

  const response = await fetch(account.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
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

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const token = authorization.slice("Bearer ".length);
  const { data: authData, error: authError } = await userClient.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "invalid_session" }, 401);

  let body: { message_id?: unknown };
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
  if (typeof body.message_id !== "string" || body.message_id.length > 64) {
    return json({ error: "message_id_required" }, 400);
  }

  const admin = createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: message, error: messageError } = await admin.from("messages")
    .select("id,conversation_id,sender_id")
    .eq("id", body.message_id).maybeSingle();
  if (messageError || !message || message.sender_id !== authData.user.id) {
    return json({ error: "message_not_found_or_not_owned" }, 404);
  }

  const { data: members, error: membersError } = await admin.from("conversation_members")
    .select("user_id").eq("conversation_id", message.conversation_id)
    .neq("user_id", authData.user.id);
  if (membersError) return json({ error: "recipient_lookup_failed" }, 500);
  const recipientIds = (members ?? []).map((m) => m.user_id as string);
  if (recipientIds.length === 0) return json({ sent: 0, skipped: 0 });

  const { data: blocks, error: blocksError } = await admin.from("user_blocks")
    .select("blocker_id,blocked_id")
    .or(`and(blocker_id.in.(${recipientIds.join(",")}),blocked_id.eq.${authData.user.id}),and(blocker_id.eq.${authData.user.id},blocked_id.in.(${recipientIds.join(",")}))`);
  if (blocksError) return json({ error: "privacy_check_failed" }, 500);
  const blocked = new Set<string>();
  for (const row of blocks ?? []) {
    if (row.blocker_id === authData.user.id) blocked.add(row.blocked_id);
    else blocked.add(row.blocker_id);
  }
  const allowedIds = recipientIds.filter((id) => !blocked.has(id));
  if (allowedIds.length === 0) return json({ sent: 0, skipped: recipientIds.length });

  const { data: devices, error: devicesError } = await admin.from("device_push_tokens")
    .select("id,user_id,token,platform").in("user_id", allowedIds).is("disabled_at", null);
  if (devicesError) return json({ error: "device_lookup_failed" }, 500);
  if (!devices?.length) return json({ sent: 0, skipped: recipientIds.length });

  const rawAccount = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!rawAccount) return json({ error: "push_provider_not_configured", sent: 0 }, 503);
  let account: ServiceAccount;
  try { account = JSON.parse(rawAccount); } catch { return json({ error: "invalid_fcm_service_account" }, 500); }
  if (!account.client_email || !account.private_key || !account.project_id) {
    return json({ error: "invalid_fcm_service_account" }, 500);
  }

  try {
    const accessToken = await fcmAccessToken(account);
    let sent = 0;
    let failed = 0;
    for (const device of devices) {
      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: device.token,
            notification: { title: "WASEL", body: "You have a new message" },
            data: { type: "message", conversation_id: message.conversation_id, message_id: message.id },
            android: { priority: "high" },
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
    return json({ sent, failed, skipped: recipientIds.length - allowedIds.length });
  } catch {
    return json({ error: "push_delivery_failed" }, 502);
  }
});
