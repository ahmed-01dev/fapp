import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "authentication_required" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  if (!url || !anonKey) return json({ error: "server_not_configured" }, 500);

  const client = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const token = authorization.slice("Bearer ".length);
  const { data: authData, error: authError } = await client.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "invalid_session" }, 401);

  // Display name is user-provided profile data, never used for authorization.
  const metadataName = authData.user.user_metadata?.display_name;
  const candidate = typeof metadataName === "string" ? metadataName.trim() : "";
  const displayName = candidate.length > 0
    ? candidate.slice(0, 40)
    : "New user";

  const { error: insertError } = await client
    .from("profiles")
    .upsert(
      { id: authData.user.id, display_name: displayName },
      { onConflict: "id", ignoreDuplicates: true },
    );

  if (insertError) return json({ error: "profile_bootstrap_failed" }, 500);

  // Always read back the row; ignoreDuplicates can return no row on an existing profile.
  const { data: profile, error: readError } = await client
    .from("profiles")
    .select("id, display_name, username")
    .eq("id", authData.user.id)
    .maybeSingle();

  if (readError || !profile) return json({ error: "profile_bootstrap_failed" }, 500);
  return json({ profile });
});
