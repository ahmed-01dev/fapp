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

async function createTurnPassword(username: string, sharedSecret: string): Promise<string> {
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
    { urls: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"] },
  ];

  const turnUrls = (Deno.env.get("TURN_URLS") ?? "")
    .split(/[;,]/).map((value) => value.trim())
    .filter((value) => /^(turn|turns):/i.test(value));
  const turnSecret = Deno.env.get("TURN_SHARED_SECRET");

  if (turnUrls.length > 0 && turnSecret) {
    const expiresAt = Math.floor(Date.now() / 1000) + 600;
    const username = `${expiresAt}:${authData.user.id}`;
    const credential = await createTurnPassword(username, turnSecret);
    iceServers.push({ urls: turnUrls, username, credential });
  }

  return json({
    iceServers,
    turnConfigured: turnUrls.length > 0 && Boolean(turnSecret),
    credentialTtlSeconds: 600,
  });
});
