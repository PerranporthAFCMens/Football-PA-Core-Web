import { runAll, verifyTransaction } from "./monzo-pot-worker.ts";
import assert from "node:assert/strict";

function setup(opts: any = {}) {
  const calls: string[] = [];
  const finished: Record<string, any> = {};
  const saved: any[] = [];
  let released: any = null;
  const txs: Record<string, any> = {
    tx_ok: { id: "tx_ok", account_id: "acc_A", amount: 600, currency: "GBP", scheme: "p2p_payment" },
    tx_small: { id: "tx_small", account_id: "acc_A", amount: 200, currency: "GBP" },
    tx_other: { id: "tx_other", account_id: "acc_B", amount: 600, currency: "GBP" },
    tx_out: { id: "tx_out", account_id: "acc_A", amount: -600, currency: "GBP" },
    ...(opts.txs || {}),
  };
  const transfers = opts.transfers ?? [
    { id: "t1", monzo_transaction_id: "tx_ok", amount_pence: 600, dedupe_id: "fpa-pot-t1", pot_id: "pot_1" },
    { id: "t2", monzo_transaction_id: "tx_small", amount_pence: 300, dedupe_id: "fpa-pot-t2", pot_id: "pot_1" },
    { id: "t3", monzo_transaction_id: "tx_other", amount_pence: 300, dedupe_id: "fpa-pot-t3", pot_id: "pot_1" },
    { id: "t4", monzo_transaction_id: "tx_out", amount_pence: 300, dedupe_id: "fpa-pot-t4", pot_id: "pot_1" },
    { id: "t5", monzo_transaction_id: "tx_missing", amount_pence: 300, dedupe_id: "fpa-pot-t5", pot_id: "pot_1" },
  ];
  const lease = { connection_id: "c1", monzo_account_id: "acc_A", pot_id: "pot_1", access_token: "AT", refresh_token: "RT",
                  expires_at: opts.expires_at ?? new Date(Date.now() + 3600e3).toISOString() };
  const rpc = async (fn: string, args: any) => {
    calls.push(fn);
    if (fn === "monzo_worker_connections") return { data: ["c1"], error: null };
    if (fn === "monzo_worker_lease") return { data: opts.noLease ? null : lease, error: null };
    if (fn === "monzo_worker_save_tokens") { saved.push(args); return { data: opts.saveFails ? false : true, error: null }; }
    if (fn === "monzo_worker_claim") return { data: transfers, error: null };
    if (fn === "monzo_worker_finish") { finished[args.p_transfer_id] = args; return { data: null, error: null }; }
    if (fn === "monzo_worker_release") { released = args; return { data: null, error: null }; }
    if (fn === "monzo_worker_transfer_label") return { data: "Subs: Dan Gilbert (Porthleven 2nd)", error: null };
    throw new Error("unexpected rpc " + fn);
  };
  const deposits: any[] = [];
  const notes: any[] = [];
  const fetchFn = async (url: string, init: any) => {
    const u = new URL(url);
    const auth = init.headers?.Authorization;
    const r = (status: number, body: any) => new Response(JSON.stringify(body), { status });
    if (u.pathname === "/oauth2/token") {
      if (opts.refreshFails) return r(401, { code: "unauthorized" });
      return r(200, { access_token: "AT2", refresh_token: "RT2", expires_in: 21600 });
    }
    if (opts.forbidden && auth) return r(403, {});
    if (u.pathname === "/transactions" && init.method === "GET") {
      return r(200, { transactions: [
        { id: "tx_old_pot", amount: -600, scheme: "uk_retail_pot", notes: "already", metadata: { pot_id: "pot_1" } },
        { id: "tx_pot_new", amount: -600, scheme: "uk_retail_pot", notes: "", metadata: { pot_id: "pot_1" } },
      ] });
    }
    if (u.pathname.startsWith("/transactions/") && init.method === "PATCH") {
      notes.push({ id: decodeURIComponent(u.pathname.split("/")[2]), ...Object.fromEntries(new URLSearchParams(init.body)) });
      return r(opts.patchFails ? 500 : 200, {});
    }
    if (u.pathname === "/pots") return r(200, { pots: [{ id: "pot_1", name: "Perranporth Subs", deleted: false }] });
    if (u.pathname.startsWith("/transactions/")) {
      const id = decodeURIComponent(u.pathname.split("/")[2]);
      return txs[id] ? r(200, { transaction: txs[id] }) : r(404, { code: "not_found" });
    }
    if (u.pathname === "/pots/pot_1/deposit") {
      assert.equal(init.method, "PUT");
      const f = new URLSearchParams(init.body);
      deposits.push(Object.fromEntries(f));
      if (opts.depositStatus) return r(opts.depositStatus, { message: "nope" });
      return r(200, { id: "pot_1", balance: 600 });
    }
    return r(500, {});
  };
  const deps = { rpc, fetch: fetchFn as any, clientId: "cid", clientSecret: "cs", holder: "h1" };
  return { deps, calls, finished, saved, deposits, notes, get released() { return released; } };
}

// 1. Normal run: only the genuine payment is deposited; others rejected.
{
  const s = setup();
  const [res] = await runAll(s.deps);
  assert.equal(s.deposits.length, 1);
  assert.deepEqual(s.deposits[0], { source_account_id: "acc_A", amount: "600", dedupe_id: "fpa-pot-t1" });
  assert.equal(s.finished.t1.p_status, "completed");
  for (const t of ["t2", "t3", "t4", "t5"]) assert.equal(s.finished[t].p_status, "rejected", t);
  assert.match(s.finished.t2.p_error, /smaller/);
  assert.match(s.finished.t3.p_error, /not in the subs account/);
  assert.match(s.finished.t4.p_error, /not incoming/);
  assert.equal(s.saved.length, 0, "no refresh when token is fresh");
  assert.equal(s.released.p_holder, "h1");
  assert.equal(s.released.p_error, null);
  assert.equal(res.completed, 1); assert.equal(res.rejected, 4);
  assert.deepEqual(s.notes, [{ id: "tx_pot_new", "metadata[notes]": "Subs: Dan Gilbert (Porthleven 2nd)" }]);
  assert.match(s.finished.t1.p_ref, /noted tx_pot_new/);
  console.log("ok 1 normal run (and labelled)");
}
// 2. Expiring token: refresh and save before any other Monzo call.
{
  const s = setup({ expires_at: new Date(Date.now() + 60e3).toISOString() });
  await runAll(s.deps);
  assert.equal(s.saved.length, 1);
  assert.equal(s.saved[0].p_refresh, "RT2");
  assert.ok(s.calls.indexOf("monzo_worker_save_tokens") < s.calls.indexOf("monzo_worker_finish"));
  console.log("ok 2 refresh saved first");
}
// 2b. Nothing due: no Monzo calls, no refresh.
{
  const s = setup({ expires_at: "2020-01-01T00:00:00Z", transfers: [] });
  const realFetch = s.deps.fetch;
  let fetches = 0;
  s.deps.fetch = (async (...a: any[]) => { fetches++; return (realFetch as any)(...a); }) as any;
  await runAll(s.deps);
  assert.equal(fetches, 0);
  assert.equal(s.released.p_error, null);
  console.log("ok 2b idle run makes no Monzo calls");
}
// 3. Refresh fails: nothing claimed, error recorded on release.
{
  const s = setup({ expires_at: "2020-01-01T00:00:00Z", refreshFails: true });
  const [res] = await runAll(s.deps);
  assert.equal(s.finished.t1.p_status, "pending", "claimed rows put back");
  assert.match(s.released.p_error, /refresh failed/);
  assert.equal(s.deposits.length, 0);
  console.log("ok 3 refresh failure stops run", res.error);
}
// 4. Save of new tokens refused (lost lease): stop before claiming.
{
  const s = setup({ expires_at: "2020-01-01T00:00:00Z", saveFails: true });
  await runAll(s.deps);
  assert.equal(s.deposits.length, 0);
  assert.equal(s.finished.t1.p_status, "pending");
  console.log("ok 4 save refused stops run");
}
// 5. Lease held by another run: nothing happens, no release.
{
  const s = setup({ noLease: true });
  const [res] = await runAll(s.deps);
  assert.deepEqual(s.calls, ["monzo_worker_connections", "monzo_worker_lease"]);
  assert.equal(res.error, "Another run is busy");
  console.log("ok 5 busy lease");
}
// 6. Not approved in the app (403): nothing claimed.
{
  const s = setup({ forbidden: true });
  await runAll(s.deps);
  assert.equal(s.deposits.length, 0);
  assert.equal(Object.values(s.finished).filter((f: any) => f.p_status === "pending").length, 5);
  assert.match(s.released.p_error, /Approve access/);
  console.log("ok 6 403 stops run");
}
// 7. Deposit 500: retry later (pending); deposit 400: failed.
{
  const s = setup({ depositStatus: 503, transfers: [{ id: "t1", monzo_transaction_id: "tx_ok", amount_pence: 600, dedupe_id: "d", pot_id: "pot_1" }] });
  await runAll(s.deps);
  assert.equal(s.finished.t1.p_status, "pending");
  const s2 = setup({ depositStatus: 400, transfers: [{ id: "t1", monzo_transaction_id: "tx_ok", amount_pence: 600, dedupe_id: "d", pot_id: "pot_1" }] });
  await runAll(s2.deps);
  assert.equal(s2.finished.t1.p_status, "failed");
  console.log("ok 7 deposit errors");
}
// 8. Pot changed since queued: rejected without calling Monzo.
{
  const s = setup({ transfers: [{ id: "t1", monzo_transaction_id: "tx_ok", amount_pence: 600, dedupe_id: "d", pot_id: "pot_OLD" }] });
  await runAll(s.deps);
  assert.equal(s.finished.t1.p_status, "rejected");
  assert.equal(s.deposits.length, 0);
  console.log("ok 8 pot changed");
}
// 8b. Labelling fails: transfer still completed.
{
  const s = setup({ patchFails: true, transfers: [{ id: "t1", monzo_transaction_id: "tx_ok", amount_pence: 600, dedupe_id: "d", pot_id: "pot_1" }] });
  await runAll(s.deps);
  assert.equal(s.finished.t1.p_status, "completed");
  assert.doesNotMatch(s.finished.t1.p_ref, /noted/);
  console.log("ok 8b label failure harmless");
}
// 9. verifyTransaction edge cases
assert.match(verifyTransaction({ account_id: "a", amount: 300, currency: "EUR" }, "a", 300)!, /pounds/);
assert.match(verifyTransaction({ account_id: "a", amount: 300, currency: "GBP", decline_reason: "X" }, "a", 300)!, /declined/);
assert.match(verifyTransaction({ account_id: "a", amount: 300, currency: "GBP", scheme: "uk_retail_pot" }, "a", 300)!, /pot/);
assert.equal(verifyTransaction({ account_id: "a", amount: 300, currency: "GBP" }, "a", 300), null);
console.log("ok 9 verify");
