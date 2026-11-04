// Football PA: move confirmed subs money into the club's Monzo pot.
// Plain logic with no Deno or Supabase imports, so it can be tested on its own (monzo-pot-transfer/index.ts wires it up).
//
// For each switched-on connection:
//  1. Take the token lease (only one run at a time can refresh tokens), refresh the token if it is
//     close to expiring and save the new pair straight away.
//  2. Claim due transfers (if none, stop: no Monzo calls), then check the pot belongs to the account.
//  3. For each one, fetch the original payment from Monzo again and check it is
//     an incoming GBP payment into this account for at least the amount, then deposit with the
//     transfer's fixed dedupe_id (a retry can never move the money twice).
//  4. Release the lease.

export const MONZO_API = "https://api.monzo.com";

export type Rpc = (fn: string, args: Record<string, unknown>) => Promise<{ data: any; error: { message: string } | null }>;

export interface Deps {
  rpc: Rpc;
  fetch: typeof fetch;
  clientId: string;
  clientSecret: string;
  holder: string; // a fresh uuid per run
  now?: () => Date;
  log?: (msg: string, detail?: Record<string, unknown>) => void;
  timeoutMs?: number;
}

export interface Transfer {
  id: string;
  monzo_transaction_id: string;
  amount_pence: number;
  dedupe_id: string;
  pot_id: string | null;
}

type Outcome = "completed" | "failed" | "rejected" | "pending";

const LEASE_SECONDS = 300;
const CLAIM_LIMIT = 5;
const REFRESH_MARGIN_MS = 5 * 60 * 1000;

class AuthError extends Error {}

export async function call(deps: Deps, path: string, init: RequestInit & { token: string }) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), deps.timeoutMs ?? 10_000);
  try {
    const res = await deps.fetch(MONZO_API + path, {
      method: init.method,
      body: init.body,
      headers: { Authorization: `Bearer ${init.token}`, ...(init.body ? { "Content-Type": "application/x-www-form-urlencoded" } : {}) },
      signal: ctl.signal,
    });
    const body = await res.json().catch(() => null);
    return { status: res.status, body };
  } catch (e) {
    return { status: 0, body: null, error: String((e as Error)?.message || e) };
  } finally {
    clearTimeout(timer);
  }
}

// Why a payment must not be moved, or null if it is fine.
export function verifyTransaction(tx: any, accountId: string, amountPence: number): string | null {
  if (!tx || typeof tx !== "object") return "Monzo did not return the payment";
  if (tx.account_id !== accountId) return "Payment is not in the subs account";
  if (tx.currency !== "GBP") return "Payment is not in pounds";
  if (!(typeof tx.amount === "number" && tx.amount > 0)) return "Payment is not incoming";
  if (tx.amount < amountPence) return "Payment is smaller than the transfer";
  if (tx.decline_reason) return "Payment was declined";
  if (tx.scheme === "uk_retail_pot") return "Payment is a pot movement";
  return null;
}

export async function refreshIfNeeded(deps: Deps, lease: any): Promise<string> {
  const now = (deps.now ?? (() => new Date()))().getTime();
  const expires = lease.expires_at ? new Date(lease.expires_at).getTime() : 0;
  if (lease.access_token && expires - now > REFRESH_MARGIN_MS) return lease.access_token;

  const res = await deps.fetch(MONZO_API + "/oauth2/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      client_id: deps.clientId,
      client_secret: deps.clientSecret,
      refresh_token: lease.refresh_token,
    }).toString(),
  });
  const body = await res.json().catch(() => null);
  if (!res.ok || !body?.access_token || !body?.refresh_token) {
    throw new AuthError(`Monzo login refresh failed (${res.status}). Log in again with the monzo-oauth link.`);
  }
  // The old refresh token is now dead, so save the new pair before doing anything else.
  const expiresAt = new Date(now + (Number(body.expires_in) || 21600) * 1000).toISOString();
  const saved = await deps.rpc("monzo_worker_save_tokens", {
    p_connection_id: lease.connection_id, p_holder: deps.holder,
    p_access: body.access_token, p_refresh: body.refresh_token, p_expires_at: expiresAt,
  });
  if (saved.error || saved.data !== true) {
    throw new AuthError("New Monzo login could not be saved. Log in again with the monzo-oauth link.");
  }
  return body.access_token;
}

// Best effort: put the player's name on the pot transfer in the Monzo app. Monzo's deposit call takes
// no reference, so find the transfer it just made and add a note. Never affects the transfer itself.
export async function labelDeposit(deps: Deps, token: string, accountId: string, potId: string, t: Transfer, since: string): Promise<string | null> {
  try {
    const lab = await deps.rpc("monzo_worker_transfer_label", { p_transfer_id: t.id });
    const label = typeof lab.data === "string" ? lab.data : null;
    if (lab.error || !label) return null;
    const list = await call(deps, `/transactions?account_id=${encodeURIComponent(accountId)}&since=${encodeURIComponent(since)}&limit=50`, { method: "GET", token });
    if (list.status !== 200) return null;
    const tx = (list.body?.transactions ?? [])
      .filter((x: any) => x.amount === -t.amount_pence && x.scheme === "uk_retail_pot" && !x.notes &&
                          (!x.metadata?.pot_id || x.metadata.pot_id === potId))
      .pop(); // newest last
    if (!tx?.id) return null;
    const res = await call(deps, `/transactions/${encodeURIComponent(tx.id)}`, {
      method: "PATCH", token, body: new URLSearchParams({ "metadata[notes]": label }).toString(),
    });
    return res.status === 200 ? tx.id : null;
  } catch {
    return null;
  }
}

async function processOne(deps: Deps, token: string, accountId: string, potId: string, t: Transfer): Promise<{ status: Outcome; ref?: string; error?: string }> {
  if (t.pot_id && t.pot_id !== potId) return { status: "rejected", error: "Pot changed since the transfer was queued" };

  const got = await call(deps, `/transactions/${encodeURIComponent(t.monzo_transaction_id)}`, { method: "GET", token });
  if (got.status === 401 || got.status === 403) throw new AuthError(`Monzo refused access (${got.status})`);
  if (got.status === 404 || got.status === 400) return { status: "rejected", error: `Monzo could not find the payment (${got.status})` };
  if (got.status !== 200) return { status: "pending", error: got.error || `Monzo error fetching payment (${got.status})` };

  const problem = verifyTransaction(got.body?.transaction, accountId, t.amount_pence);
  if (problem) return { status: "rejected", error: problem };

  const since = new Date((deps.now ?? (() => new Date()))().getTime() - 60_000).toISOString();
  const dep = await call(deps, `/pots/${encodeURIComponent(potId)}/deposit`, {
    method: "PUT",
    token,
    body: new URLSearchParams({ source_account_id: accountId, amount: String(t.amount_pence), dedupe_id: t.dedupe_id }).toString(),
  });
  if (dep.status === 200) {
    const noted = await labelDeposit(deps, token, accountId, potId, t, since);
    return { status: "completed", ref: noted ? `pot ${potId}, noted ${noted}` : `pot ${potId}` };
  }
  if (dep.status === 401 || dep.status === 403) throw new AuthError(`Monzo refused the deposit (${dep.status})`);
  // A timeout or server error may still have moved the money; retrying with the same dedupe_id is safe.
  if (dep.status === 0 || dep.status === 429 || dep.status >= 500) return { status: "pending", error: dep.error || `Monzo deposit error (${dep.status})` };
  return { status: "failed", error: `Monzo rejected the deposit (${dep.status}): ${dep.body?.message ?? dep.body?.code ?? ""}`.trim() };
}

export async function runConnection(deps: Deps, connectionId: string) {
  const log = deps.log ?? (() => {});
  const summary = { connection_id: connectionId, leased: false, claimed: 0, completed: 0, pending: 0, failed: 0, rejected: 0, error: null as string | null };

  const leased = await deps.rpc("monzo_worker_lease", { p_connection_id: connectionId, p_holder: deps.holder, p_seconds: LEASE_SECONDS });
  if (leased.error) { summary.error = leased.error.message; return summary; }
  if (!leased.data) { summary.error = "Another run is busy"; return summary; }
  summary.leased = true;
  const lease = leased.data;
  let lastError: string | null = null;

  let rows: Transfer[] = [];
  let done = 0;
  try {
    // Claim first, so an idle run (most minutes) makes no calls to Monzo at all.
    const claimed = await deps.rpc("monzo_worker_claim", { p_connection_id: connectionId, p_holder: deps.holder, p_limit: CLAIM_LIMIT });
    if (claimed.error) throw new Error(claimed.error.message);
    rows = claimed.data ?? [];
    summary.claimed = rows.length;
    if (rows.length === 0) return summary;

    const token = await refreshIfNeeded(deps, lease);
    if (!lease.pot_id) throw new Error("No pot set");

    const pots = await call(deps, `/pots?current_account_id=${encodeURIComponent(lease.monzo_account_id)}`, { method: "GET", token });
    if (pots.status === 401 || pots.status === 403) throw new AuthError(`Monzo refused access (${pots.status}). Approve access in the Monzo app.`);
    if (pots.status !== 200) throw new Error(`Could not check the pot (${pots.status || pots.error})`);
    const pot = (pots.body?.pots ?? []).find((p: any) => p.id === lease.pot_id);
    if (!pot || pot.deleted) throw new Error("The subs pot was not found on this account");

    for (; done < rows.length; done++) {
      const t = rows[done];
      const r = await processOne(deps, token, lease.monzo_account_id, lease.pot_id, t);
      await deps.rpc("monzo_worker_finish", { p_transfer_id: t.id, p_status: r.status, p_ref: r.ref ?? null, p_error: r.error ?? null });
      summary[r.status]++;
      log("transfer", { id: t.id, status: r.status, error: r.error });
    }
  } catch (e) {
    lastError = String((e as Error)?.message || e);
    summary.error = lastError;
    // Anything claimed but not finished goes back for the next run (same dedupe_id, so safe).
    for (const rest of rows.slice(done)) {
      await deps.rpc("monzo_worker_finish", { p_transfer_id: rest.id, p_status: "pending", p_ref: null, p_error: lastError });
      summary.pending++;
    }
    log("connection error", { connection_id: connectionId, error: lastError });
  } finally {
    await deps.rpc("monzo_worker_release", { p_connection_id: connectionId, p_holder: deps.holder, p_error: lastError });
  }
  return summary;
}

export async function runAll(deps: Deps) {
  const conns = await deps.rpc("monzo_worker_connections", {});
  if (conns.error) throw new Error(conns.error.message);
  const out = [];
  for (const id of conns.data ?? []) out.push(await runConnection(deps, String(id)));
  return out;
}
