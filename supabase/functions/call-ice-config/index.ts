import { createClient } from "npm:@supabase/supabase-js@2";

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

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

async function createCoturnPassword(username: string, sharedSecret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(sharedSecret),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(username));
  return base64(new Uint8Array(signature));
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

  let body: { call_id?: unknown };
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
  if (typeof body.call_id !== "string" || body.call_id.length > 64) {
    return json({ error: "call_id_required" }, 400);
  }

  const admin = createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: call, error: callError } = await admin.from("call_sessions")
    .select("id,caller_id,callee_id,status")
    .eq("id", body.call_id)
    .maybeSingle();

  if (callError || !call || ![call.caller_id, call.callee_id].includes(authData.user.id)) {
    return json({ error: "call_not_found_or_not_participant" }, 404);
  }
  if (!["ringing", "accepted"].includes(call.status)) {
    return json({ error: "call_not_active" }, 409);
  }

  const iceServers: Array<Record<string, unknown>> = [
    { urls: ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302"] },
  ];
  const cloudflareKeyId = Deno.env.get("CLOUDFLARE_TURN_KEY_ID");
  const cloudflareApiToken = Deno.env.get("CLOUDFLARE_TURN_KEY_SECRET");

  // Cloudflare credentials are generated server-side and are short-lived.
  if (cloudflareKeyId && cloudflareApiToken) {
    const ttl = 86400;
    const response = await fetch(
      `https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(cloudflareKeyId)}/credentials/generate-ice-servers`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${cloudflareApiToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ ttl }),
      },
    );
    if (!response.ok) {
      // Do not log or return provider response bodies or credentials.
      return json({ error: "turn_provider_unavailable", provider: "cloudflare", status: response.status }, 502);
    }
    const result = await response.json();
    if (!Array.isArray(result?.iceServers) || result.iceServers.length === 0) {
      return json({ error: "turn_provider_invalid_response" }, 502);
    }
    return json({
      iceServers: result.iceServers,
      turnConfigured: true,
      turnProvider: "cloudflare",
      credentialTtlSeconds: ttl,
    });
  }

  // Backward-compatible coturn mode, if a self-hosted relay is configured.
  const turnUrls = (Deno.env.get("TURN_URLS") ?? "")
    .split(/[;,]/).map((value) => value.trim())
    .filter((value) => /^(turn|turns):/i.test(value));
  const turnSecret = Deno.env.get("TURN_SHARED_SECRET");
  if (turnUrls.length > 0 && turnSecret) {
    const expiresAt = Math.floor(Date.now() / 1000) + 600;
    const username = `${expiresAt}:${authData.user.id}`;
    const credential = await createCoturnPassword(username, turnSecret);
    iceServers.push({ urls: turnUrls, username, credential });
    return json({
      iceServers,
      turnConfigured: true,
      turnProvider: "coturn",
      credentialTtlSeconds: 600,
    });
  }

  return json({
    iceServers,
    turnConfigured: false,
    turnProvider: null,
    credentialTtlSeconds: 0,
  });
});
