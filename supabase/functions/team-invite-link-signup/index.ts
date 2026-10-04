// Football PA: create a staff account from a shareable invite link.
// Called by join.html when the person does not have a Football PA account yet.
// The invite link itself is the proof they were invited, so the email address
// is marked as confirmed and the link is used up in the same step.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const body = await req.json().catch(() => ({}));
    const token = String(body.token || "");
    const email = String(body.email || "").trim().toLowerCase();
    const password = String(body.password || "");
    const name = String(body.name || "").trim().slice(0, 80);

    if (!token) return json({ error: "This invite link is not valid." }, 400);
    if (!email || !email.includes("@")) return json({ error: "Enter a valid email address." }, 400);
    if (password.length < 8) return json({ error: "Use a password of at least 8 characters." }, 400);
    if (!name) return json({ error: "Enter your name." }, 400);

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // Check the link before creating anything.
    const { data: peek, error: peekError } = await admin.rpc("peek_team_invite_link", { p_token: token });
    if (peekError) return json({ error: peekError.message }, 400);
    if (!peek?.valid) return json({ error: peek?.reason || "This invite link is not valid." }, 400);

    // Create the account.
    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { display_name: name, footballpa_staff_invite: true },
    });
    if (createError || !created?.user) {
      const msg = createError?.message || "";
      if (/already|registered|exists/i.test(msg)) {
        return json({ status: "existing_account", message: "You already have a Football PA account. Sign in to accept the invite." }, 409);
      }
      return json({ error: msg || "Could not create your account." }, 400);
    }

    // Use up the link and give team access. If that fails, remove the new account again.
    const { data: claimed, error: claimError } = await admin.rpc("claim_team_invite_link_for_user", {
      p_token: token,
      p_user_id: created.user.id,
    });
    if (claimError) {
      await admin.auth.admin.deleteUser(created.user.id).catch(() => {});
      return json({ error: claimError.message }, 400);
    }

    return json({ ok: true, status: "created", team_id: claimed?.team_id || peek.team_id });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : "Unable to accept the invite." }, 500);
  }
});
