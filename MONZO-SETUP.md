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
