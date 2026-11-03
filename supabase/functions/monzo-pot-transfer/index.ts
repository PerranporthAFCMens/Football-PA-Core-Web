// Football PA: scheduled worker that moves confirmed subs into the Monzo pot (logic in _shared/monzo-pot-worker.ts).
// Called by a pg_cron job with the header x-worker-secret. Deploy with verify_jwt off.
// Does nothing unless the MONZO_TRANSFERS_ENABLED secret is "true" AND the connection has
// pot_id and transfers_from set in the database.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { runAll } from "../_shared/monzo-pot-worker.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function sameSecret(a: string, b: string) {
  if (!a || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!sameSecret(req.headers.get("x-worker-secret") || "", Deno.env.get("MONZO_WORKER_SECRET") || "")) {
    return json({ error: "Not found" }, 404);
  }
  if (Deno.env.get("MONZO_TRANSFERS_ENABLED") !== "true") return json({ ok: true, skipped: "transfers_disabled" });

  const clientId = Deno.env.get("MONZO_CLIENT_ID") || "";
  const clientSecret = Deno.env.get("MONZO_CLIENT_SECRET") || "";
  if (!clientId || !clientSecret) return json({ error: "Monzo client not configured" }, 500);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  try {
    const results = await runAll({
      rpc: async (fn, args) => {
        const { data, error } = await admin.rpc(fn, args);
        return { data, error: error ? { message: error.message } : null };
      },
      fetch,
      clientId,
      clientSecret,
      holder: crypto.randomUUID(),
      // Outcomes only: no names, amounts or tokens in the logs.
      log: (msg, detail) => console.log("monzo-pot-transfer", msg, JSON.stringify(detail ?? {})),
    });
    console.log("monzo-pot-transfer run", JSON.stringify(results));
    return json({ ok: true, results });
  } catch (e) {
    console.error("monzo-pot-transfer failed", String((e as Error)?.message || e));
    return json({ error: "Worker failed" }, 500);
  }
});
