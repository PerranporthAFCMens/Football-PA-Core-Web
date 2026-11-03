// Football PA: receive Monzo "transaction.created" webhooks and queue subs payments.
// Monzo does not sign its webhooks, so the webhook URL carries a secret (?secret=...) that must
// match the monzo_connections row for the Monzo account. All matching happens in the database
// function record_monzo_payment(). This function never marks games paid itself: a manager
// confirms that on the Subs Tracker.
// Deploy with verify_jwt off (Monzo cannot send a Supabase login).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const secret = new URL(req.url).searchParams.get("secret") || "";
  if (!secret) return json({ error: "Not found" }, 404);

  const body = await req.json().catch(() => null);
  if (!body || typeof body !== "object") return json({ error: "Bad request" }, 400);
  // Other event types: say OK so Monzo does not keep retrying.
  if (body.type !== "transaction.created" || !body.data?.id) return json({ ok: true, skipped: "not_a_transaction" });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await admin.rpc("record_monzo_payment", { p_secret: secret, p_tx: body.data });
  if (error) {
    // A 500 makes Monzo retry (up to 5 times), which is what we want for a temporary database problem.
    console.error("record_monzo_payment failed", error.message);
    return json({ error: "Could not record payment" }, 500);
  }
  // Outcome only (no names or amounts), so the Supabase logs show why a payment was or wasn't kept.
  console.log("monzo-webhook", JSON.stringify({ ok: data?.ok, skipped: data?.skipped, matched: data?.matched, method: data?.method, reason: data?.reason }));
  if (data?.ok === false) return json({ error: "Not found" }, 404);
  return json(data);
});
