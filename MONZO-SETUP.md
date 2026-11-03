# Monzo payments into the Subs Tracker

When someone pays into the connected Monzo account, the payment appears on the Subs Tracker
(Summary tab, "Monzo payments"). Football PA works out who paid and which games it covers.
A manager taps **Apply** to mark those games paid.

## How a payment is matched to a player

1. **Remembered payer.** If a manager has linked this payer before, it matches straight away.
   Bank details (sort code and account number, or the Monzo user) are checked first, then the name.
2. **Name on the account** is exactly one current player's name. Titles, capitals and punctuation
   are ignored ("MR TOM O'NEILL" matches Tom O'Neill).
3. **Initial and surname** ("J SMITH") if only one player fits.
4. Otherwise it goes to **"Who is this from?"**. Pick the player, leave "Remember this payer" ticked,
   and the next payment from that account matches by itself. This is how players who pay from a
   partner's or parent's account are handled.

Remembered payers can be removed under "Remembered payers".

## Which games a payment covers

The amount is divided by the per-game charge. That many games are marked paid, oldest unpaid
first, then upcoming games. Anything that does not divide evenly is shown as "left over".

## Privacy

The account also receives money that is not subs. A payment from someone who is **not** a known
player is only kept if it is a whole number of games (up to 10) or the reference contains "sub".
Everything else is never stored. Anything that slips through can be cleared with **Not subs**.

## One-off setup

### 1. Database and webhook receiver (needs Adam's approval of the exact SQL)

- Apply `supabase/migrations/20261103210000_monzo_subs_payments.sql`.
- Deploy the edge function `monzo-webhook` with **verify_jwt off** (Monzo cannot log in to Supabase;
  the secret in the webhook address is the check).

### 2. Find the Monzo account id

1. Go to developers.monzo.com and sign in with the email for the Monzo account.
2. Open **API Playground**. Approve the request in the Monzo app when it pops up.
3. Run `GET /accounts`. Copy the `id` of the account the subs are paid into (it starts `acc_`).

You do not need to create an OAuth client: the Playground token is enough to register the webhook,
and the webhook keeps working after that token expires.

### 3. Link the account to the team (SQL, run once)

```sql
insert into public.monzo_connections (club_id, team_id, monzo_account_id)
select t.club_id, t.id, 'acc_PASTE_HERE' from public.teams t where t.id = 'TEAM_ID_HERE'
returning webhook_secret;
```

Keep the `webhook_secret` it returns private.

### 4. Register the webhook (API Playground)

Run `POST /webhooks` with:

- `account_id`: the `acc_...` id
- `url`: `https://hennzggqaquevqgiucqn.supabase.co/functions/v1/monzo-webhook?secret=THE_SECRET`

### 5. Test

Send £0.01 to the account from another account. It will not be stored (it is not a whole game), but
the edge function log in Supabase should show a 200 response with `"skipped": "not_subs"`. Then send
one game's subs from a player's account and check it appears on the Subs Tracker.

## Turning it off

Playground: `GET /webhooks`, then `DELETE /webhooks/<id>`. Or set `monzo_connections.active = false`.

## Pot transfers (built, switched off)

Subs that Football PA has marked paid can be moved automatically into the "Perranporth Subs" pot.
This is a separate process from recording payments: if Monzo's API is down, players are still
marked paid, and the transfer waits and retries.

How it works:

1. When a Monzo payment becomes "applied" (games marked paid), a row is added to
   `monzo_pot_transfers` for the amount that paid for games (any leftover stays in the account).
2. The row waits `hold_minutes` (30 by default). If a manager presses "Undo paid" on any of its
   games during the hold, the transfer is cancelled.
3. Every 10 minutes the `monzo-pot-transfer` function (pg_cron) takes the login lease, fetches the
   original payment from Monzo again and checks it is an incoming GBP payment into the subs account
   for at least the amount. Only then does it deposit, with a fixed `dedupe_id` so a retry can
   never move the money twice. Anything that fails a check is marked `rejected` and never moved.

Off switches (all three must be on for money to move):

- Secret `MONZO_TRANSFERS_ENABLED` = `true` on the edge functions.
- `monzo_connections.pot_id` set.
- `monzo_connections.transfers_from` set. Payments received before this time are never moved.
  Until it is set, every applied payment gets a `dry_run` row, which can never be moved later.

### Stage 1: install, nothing moves (needs Adam's approval of the exact SQL)

1. Apply migration `20261104090000_monzo_pot_transfers.sql`.
2. Deploy `monzo-pot-transfer` and `monzo-oauth` with verify_jwt off (both use
   `_shared/monzo-pot-worker.ts`).
3. In developers.monzo.com create a new OAuth client: Confidentiality **Confidential**, Redirect URL
   `https://hennzggqaquevqgiucqn.supabase.co/functions/v1/monzo-oauth`.
4. Supabase, Edge Functions, Secrets: `MONZO_CLIENT_ID`, `MONZO_CLIENT_SECRET`, `MONZO_WORKER_SECRET`
   (a long random string). Do not set `MONZO_TRANSFERS_ENABLED` yet.
5. Log in once: open
   `https://hennzggqaquevqgiucqn.supabase.co/functions/v1/monzo-oauth?start=1&account=acc_00009V8QqxxJjp7DnnLGmP&key=<MONZO_WORKER_SECRET>`,
   log in by email, then approve access in the Monzo app.
6. Open `...functions/v1/monzo-oauth?status=1&key=<MONZO_WORKER_SECRET>`. It should say "logged in and
   approved" and list your pots with their ids.

### Stage 2: switch on (only after review and Adam's explicit approval)

1. `update monzo_connections set pot_id = '<pot id>', transfers_from = now() where monzo_account_id = 'acc_00009V8QqxxJjp7DnnLGmP';`
2. Store the worker secret in Vault as `monzo_worker_secret` and schedule the worker every 10 minutes
   with pg_cron + pg_net (header `x-worker-secret`).
3. Set `MONZO_TRANSFERS_ENABLED` = `true`.
4. Watch the first transfer: `select status, amount_pence, last_error from monzo_pot_transfers order by created_at desc limit 5;`

To stop at any time: remove `MONZO_TRANSFERS_ENABLED`, or `update monzo_connections set transfers_from = null`.
Transfers already completed stay in the pot; move them back in the Monzo app if needed.
