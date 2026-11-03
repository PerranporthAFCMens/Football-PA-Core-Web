// Football PA: one-time Monzo login for pot transfers. Deploy with verify_jwt off.
//
//   1. Open  <function url>?start=1&key=<MONZO_WORKER_SECRET>&account=<Monzo account id>
//      You are sent to Monzo to log in by email.
//   2. Monzo sends you back here with a code; the tokens are saved in the database (never shown).
//   3. Approve "Football PA" in the Monzo app (Monzo asks for this).
//   4. Open  <function url>?status=1&key=<MONZO_WORKER_SECRET>  to check the login and see your
//      pots with their ids (the pot id goes in monzo_connections.pot_id).
//
// Needs the secrets MONZO_CLIENT_ID, MONZO_CLIENT_SECRET (a confidential Monzo client, so it gets
// refresh tokens) and MONZO_WORKER_SECRET. The client's redirect URL must be this function's URL.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { call, refreshIfNeeded } from "../_shared/monzo-pot-worker.ts";

// Supabase serves function pages as plain text, so replies are plain text.
const text = (body: string, status = 200) =>
  new Response(body, { status, headers: { "Content-Type": "text/plain; charset=utf-8" } });

const enc = new TextEncoder();
async function sign(value: string, secret: string) {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(value)));
  return Array.from(mac, (b) => b.toString(16).padStart(2, "0")).join("");
}
function same(a: string, b: string) {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET") return text("Method not allowed", 405);
  const url = new URL(req.url);
  const q = url.searchParams;
  const clientId = Deno.env.get("MONZO_CLIENT_ID") || "";
  const clientSecret = Deno.env.get("MONZO_CLIENT_SECRET") || "";
  const workerSecret = Deno.env.get("MONZO_WORKER_SECRET") || "";
  if (!clientId || !clientSecret || !workerSecret) return text("Monzo login is not set up yet.", 500);
  const redirectUri = `${Deno.env.get("SUPABASE_URL")}/functions/v1/monzo-oauth`;
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Step 1: send the manager to Monzo.
  if (q.get("start")) {
    if (!same(q.get("key") || "", workerSecret)) return text("Not found", 404);
    const account = q.get("account") || "";
    if (!/^acc_[A-Za-z0-9]+$/.test(account)) return text("Add &account=<your Monzo account id> to the link.", 400);
    const payload = `${account}.${Date.now()}`;
    const state = `${payload}.${await sign(payload, workerSecret)}`;
    const to = new URL("https://auth.monzo.com/");
    to.search = new URLSearchParams({ client_id: clientId, redirect_uri: redirectUri, response_type: "code", state }).toString();
    return Response.redirect(to.toString(), 302);
  }

  // Step 2: Monzo sends the manager back with a code.
  if (q.get("code")) {
    const [account, ts, mac] = (q.get("state") || "").split(".");
    if (!account || !ts || !mac || !same(mac, await sign(`${account}.${ts}`, workerSecret)) || Date.now() - Number(ts) > 15 * 60 * 1000) {
      return text("This login link has expired or is not valid. Start again.", 400);
    }
    const res = await fetch("https://api.monzo.com/oauth2/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "authorization_code", client_id: clientId, client_secret: clientSecret,
        redirect_uri: redirectUri, code: q.get("code")!,
      }).toString(),
    });
    const body = await res.json().catch(() => null);
    if (!res.ok || !body?.access_token) return text(`Monzo did not accept the login (${res.status}). Start again.`, 502);
    if (!body.refresh_token) return text("Monzo gave no refresh token. The Monzo client must be set to Confidential.", 502);
    const { data, error } = await admin.rpc("monzo_store_initial_tokens", {
      p_monzo_account_id: account, p_access: body.access_token, p_refresh: body.refresh_token,
      p_expires_at: new Date(Date.now() + (Number(body.expires_in) || 21600) * 1000).toISOString(),
    });
    if (error || data !== true) return text("Logged in, but no Football PA connection uses that Monzo account.", 400);
    return text("Logged in to Monzo.\n\nNow open the Monzo app and approve access for Football PA.\nThen open the status link to check it worked and see your pot ids.");
  }

  // Step 4: check the login and list pots. Takes the token lease, so it never clashes with the worker.
  if (q.get("status")) {
    if (!same(q.get("key") || "", workerSecret)) return text("Not found", 404);
    const rpc = async (fn: string, args: Record<string, unknown>) => {
      const { data, error } = await admin.rpc(fn, args);
      return { data, error: error ? { message: error.message } : null };
    };
    const { data: conns } = await admin.from("monzo_connections").select("id, monzo_account_id, pot_id, transfers_from").eq("active", true);
    const lines: string[] = [];
    for (const c of conns ?? []) {
      const holder = crypto.randomUUID();
      const lease = await rpc("monzo_worker_lease", { p_connection_id: c.id, p_holder: holder, p_seconds: 60 });
      if (!lease.data) { lines.push(`${c.monzo_account_id}: not logged in yet (or the worker is running; try again in a minute)`); continue; }
      try {
        const deps = { rpc, fetch, clientId, clientSecret, holder };
        const token = await refreshIfNeeded(deps, lease.data);
        const pots = await call(deps, `/pots?current_account_id=${encodeURIComponent(c.monzo_account_id)}`, { method: "GET", token });
        if (pots.status === 403) { lines.push(`${c.monzo_account_id}: logged in, waiting for approval in the Monzo app`); continue; }
        if (pots.status !== 200) { lines.push(`${c.monzo_account_id}: Monzo error ${pots.status}`); continue; }
        lines.push(`${c.monzo_account_id}: logged in and approved`);
        if (lease.data.last_error) lines.push(`  last worker problem: ${lease.data.last_error}`);
        lines.push(`  pot set: ${c.pot_id ?? "none"}   transfers from: ${c.transfers_from ?? "not switched on"}`);
        for (const p of pots.body?.pots ?? []) if (!p.deleted) lines.push(`  pot "${p.name}"  id ${p.id}`);
      } catch (e) {
        lines.push(`${c.monzo_account_id}: ${String((e as Error)?.message || e)}`);
      } finally {
        // Keep any error the worker last recorded.
        await rpc("monzo_worker_release", { p_connection_id: c.id, p_holder: holder, p_error: lease.data.last_error ?? null });
      }
    }
    return text(lines.join("\n") || "No Monzo connections.");
  }

  return text("Not found", 404);
});
