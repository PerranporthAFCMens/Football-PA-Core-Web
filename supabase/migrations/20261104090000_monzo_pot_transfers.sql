-- Monzo pot transfers: move confirmed subs money into the club's Monzo pot.
-- Football PA keeps deciding who has paid (monzo_payments / subs_payments are not changed).
-- This adds a separate transfer ledger. A row is written when a Monzo payment becomes "applied";
-- the monzo-pot-transfer edge function (run on a schedule) checks the payment with Monzo and
-- moves the money.
--
-- Safeguards:
--  * Switched off until monzo_connections.transfers_from AND pot_id are set. Until then every
--    applied payment gets a final "dry_run" row that never moves money. Payments received before
--    transfers_from are never transferred, even after switching on.
--  * One ledger row per payment (unique), with a fixed Monzo dedupe_id, so a payment cannot fund
--    the pot twice even if the worker retries after a timeout.
--  * A hold (hold_minutes, default 30) before money moves. If a manager presses "Undo paid" on
--    any of the payment's games during the hold, the transfer is cancelled.
--  * The worker re-fetches the transaction from Monzo before depositing (in the edge function).
--  * A lease on the token row so only one worker run refreshes tokens at a time.
--  * Also: the existing auto-apply trigger can no longer make the webhook fail.
--
-- Rollback: drop trigger monzo_payments_queue_pot_transfer on public.monzo_payments; drop the
-- functions below (monzo_payments_queue_pot_transfer_trg, monzo_worker_*, monzo_store_initial_tokens,
-- list_monzo_pot_transfers); drop tables monzo_pot_transfers, monzo_oauth_tokens; alter table
-- monzo_connections drop column pot_id, transfers_from, hold_minutes; then restore
-- monzo_payments_auto_apply_trg from 20261103223000_monzo_auto_apply.sql.

alter table public.monzo_connections
  add column if not exists pot_id text,
  add column if not exists transfers_from timestamptz,
  add column if not exists hold_minutes integer not null default 30 check (hold_minutes between 0 and 10080);

create table if not exists public.monzo_oauth_tokens (
  connection_id uuid primary key references public.monzo_connections(id) on delete cascade,
  access_token text,
  refresh_token text,
  expires_at timestamptz,
  locked_until timestamptz,
  lock_holder uuid,
  last_error text,
  updated_at timestamptz not null default now()
);

create table if not exists public.monzo_pot_transfers (
  id uuid primary key default gen_random_uuid(),
  monzo_payment_id uuid not null unique references public.monzo_payments(id) on delete restrict,
  connection_id uuid not null references public.monzo_connections(id),
  monzo_transaction_id text not null,
  pot_id text,
  amount_pence integer not null check (amount_pence > 0),
  status text not null check (status in ('dry_run', 'pending', 'processing', 'completed', 'failed', 'rejected', 'cancelled')),
  dedupe_id text not null unique,
  release_at timestamptz not null,
  attempts integer not null default 0,
  monzo_deposit_ref text,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);
create index if not exists monzo_pot_transfers_due_idx on public.monzo_pot_transfers (status, release_at);

alter table public.monzo_oauth_tokens enable row level security;
alter table public.monzo_pot_transfers enable row level security;
revoke all on public.monzo_oauth_tokens, public.monzo_pot_transfers from public, anon, authenticated;

-- Safety fix: an error while marking games paid must never stop the payment being saved
-- (that would fail the webhook and Monzo gives up after 5 retries). The payment stays "matched".
create or replace function public.monzo_payments_auto_apply_trg()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  begin
    perform public.apply_monzo_payment(new.id);
  exception when others then
    raise warning 'apply_monzo_payment failed for %: %', new.id, sqlerrm;
  end;
  return null;
end;
$function$;

-- Write the ledger row when a payment becomes "applied". No calls out of the database here.
create or replace function public.monzo_payments_queue_pot_transfer_trg()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare
  conn public.monzo_connections;
  v_amount integer := new.amount_pence - coalesce(new.leftover_pence, 0);
  v_live boolean;
begin
  if v_amount <= 0 then return null; end if;
  select * into conn from public.monzo_connections where team_id = new.team_id and active
   order by created_at limit 1;
  if conn.id is null then return null; end if;

  v_live := conn.pot_id is not null and conn.transfers_from is not null and new.received_at >= conn.transfers_from;

  insert into public.monzo_pot_transfers (monzo_payment_id, connection_id, monzo_transaction_id, pot_id, amount_pence,
                                          status, dedupe_id, release_at)
  values (new.id, conn.id, new.monzo_transaction_id, conn.pot_id, v_amount,
          case when v_live then 'pending' else 'dry_run' end,
          'fpa-pot-' || new.id::text,
          now() + make_interval(mins => conn.hold_minutes))
  on conflict (monzo_payment_id) do nothing;
  return null;
exception when others then
  raise warning 'queue pot transfer failed for %: %', new.id, sqlerrm;
  return null;
end;
$function$;

drop trigger if exists monzo_payments_queue_pot_transfer on public.monzo_payments;
create trigger monzo_payments_queue_pot_transfer
  after update of status on public.monzo_payments
  for each row when (new.status = 'applied' and old.status is distinct from 'applied')
  execute function public.monzo_payments_queue_pot_transfer_trg();

-- ---- Worker functions (service role only) ----

-- Connections the worker should visit: switched on and logged in.
create or replace function public.monzo_worker_connections()
 returns setof uuid language sql stable security definer set search_path to 'public'
as $function$
  select c.id from public.monzo_connections c join public.monzo_oauth_tokens t on t.connection_id = c.id
   where c.active and c.pot_id is not null and c.transfers_from is not null and t.refresh_token is not null;
$function$;

-- Take the lease on a connection's tokens. Returns the connection and tokens, or null when another
-- run holds it. Only the holder may save new tokens.
create or replace function public.monzo_worker_lease(p_connection_id uuid, p_holder uuid, p_seconds integer default 120)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare t public.monzo_oauth_tokens; c public.monzo_connections;
begin
  update public.monzo_oauth_tokens
     set locked_until = now() + make_interval(secs => p_seconds), lock_holder = p_holder
   where connection_id = p_connection_id and (locked_until is null or locked_until < now())
  returning * into t;
  if t.connection_id is null then return null; end if;
  select * into c from public.monzo_connections where id = p_connection_id;
  return jsonb_build_object('connection_id', c.id, 'monzo_account_id', c.monzo_account_id, 'pot_id', c.pot_id,
                            'access_token', t.access_token, 'refresh_token', t.refresh_token, 'expires_at', t.expires_at,
                            'last_error', t.last_error);
end;
$function$;

create or replace function public.monzo_worker_release(p_connection_id uuid, p_holder uuid, p_error text default null)
 returns void language sql security definer set search_path to 'public'
as $function$
  update public.monzo_oauth_tokens set locked_until = null, lock_holder = null, last_error = p_error
   where connection_id = p_connection_id and lock_holder = p_holder;
$function$;

-- Save a refreshed token pair. Refused unless the caller holds the lease.
create or replace function public.monzo_worker_save_tokens(p_connection_id uuid, p_holder uuid, p_access text,
                                                           p_refresh text, p_expires_at timestamptz)
 returns boolean language plpgsql security definer set search_path to 'public'
as $function$
begin
  update public.monzo_oauth_tokens
     set access_token = p_access, refresh_token = p_refresh, expires_at = p_expires_at, updated_at = now(), last_error = null
   where connection_id = p_connection_id and lock_holder = p_holder and locked_until > now();
  return found;
end;
$function$;

-- First login (monzo-oauth function). Replaces any old tokens for the account's connection.
create or replace function public.monzo_store_initial_tokens(p_monzo_account_id text, p_access text, p_refresh text,
                                                             p_expires_at timestamptz)
 returns boolean language plpgsql security definer set search_path to 'public'
as $function$
declare v_conn uuid;
begin
  select id into v_conn from public.monzo_connections where monzo_account_id = p_monzo_account_id and active;
  if v_conn is null then return false; end if;
  insert into public.monzo_oauth_tokens (connection_id, access_token, refresh_token, expires_at, updated_at)
  values (v_conn, p_access, p_refresh, p_expires_at, now())
  on conflict (connection_id) do update
     set access_token = excluded.access_token, refresh_token = excluded.refresh_token,
         expires_at = excluded.expires_at, updated_at = now(), last_error = null,
         locked_until = null, lock_holder = null;
  return true;
end;
$function$;

-- Claim due transfers for the lease holder. Rows stuck in "processing" for 15 minutes (a crashed
-- run) go back round; that is safe because the deposit uses the same dedupe_id.
create or replace function public.monzo_worker_claim(p_connection_id uuid, p_holder uuid, p_limit integer default 10)
 returns setof public.monzo_pot_transfers language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not exists (select 1 from public.monzo_oauth_tokens where connection_id = p_connection_id
                  and lock_holder = p_holder and locked_until > now()) then
    return;
  end if;
  if not exists (select 1 from public.monzo_connections where id = p_connection_id
                  and pot_id is not null and transfers_from is not null and active) then
    return;
  end if;
  -- A manager pressed "Undo paid" on any of the payment's games during the hold: don't move it.
  update public.monzo_pot_transfers t
     set status = 'cancelled', last_error = 'Games no longer marked paid', updated_at = now()
    from public.monzo_payments m
   where m.id = t.monzo_payment_id and t.connection_id = p_connection_id and t.status = 'pending'
     and exists (select 1 from unnest(m.applied_fixture_ids) f(id)
                  where not exists (select 1 from public.subs_payments sp
                                     where sp.fixture_id = f.id and sp.player_id = m.player_id));
  return query
  update public.monzo_pot_transfers t
     set status = 'processing', attempts = t.attempts + 1, updated_at = now()
   where t.id in (select x.id from public.monzo_pot_transfers x
                   where x.connection_id = p_connection_id and x.release_at <= now()
                     and (x.status = 'pending' or (x.status = 'processing' and x.updated_at < now() - interval '15 minutes'))
                   order by x.created_at
                   limit p_limit
                   for update skip locked)
  returning t.*;
end;
$function$;

-- Record a transfer's outcome. p_status: completed | failed | rejected | pending (retry later).
create or replace function public.monzo_worker_finish(p_transfer_id uuid, p_status text, p_ref text default null,
                                                      p_error text default null)
 returns void language plpgsql security definer set search_path to 'public'
as $function$
begin
  if p_status not in ('completed', 'failed', 'rejected', 'pending') then raise exception 'Invalid status'; end if;
  update public.monzo_pot_transfers
     set status = case when p_status = 'pending' and attempts >= 5 then 'failed' else p_status end,
         monzo_deposit_ref = coalesce(p_ref, monzo_deposit_ref),
         last_error = p_error,
         updated_at = now(),
         completed_at = case when p_status = 'completed' then now() else completed_at end
   where id = p_transfer_id and status = 'processing';
end;
$function$;

-- Subs managers can see the ledger (read-only).
create or replace function public.list_monzo_pot_transfers(p_team_id uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_manage_subs(p_team_id) then raise exception 'You do not have permission to manage subs'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'amount_pence', t.amount_pence, 'status', t.status,
                     'payer_name', m.payer_name, 'player_name', p.display_name, 'release_at', t.release_at,
                     'completed_at', t.completed_at, 'last_error', t.last_error) order by t.created_at desc)
                   from public.monzo_pot_transfers t
                   join public.monzo_payments m on m.id = t.monzo_payment_id
                   left join public.players p on p.id = m.player_id
                  where m.team_id = p_team_id), '[]'::jsonb);
end;
$function$;

revoke all on function public.monzo_payments_queue_pot_transfer_trg() from public, anon, authenticated;
revoke all on function public.monzo_worker_connections() from public, anon, authenticated;
revoke all on function public.monzo_worker_lease(uuid, uuid, integer) from public, anon, authenticated;
revoke all on function public.monzo_worker_release(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.monzo_worker_save_tokens(uuid, uuid, text, text, timestamptz) from public, anon, authenticated;
revoke all on function public.monzo_store_initial_tokens(text, text, text, timestamptz) from public, anon, authenticated;
revoke all on function public.monzo_worker_claim(uuid, uuid, integer) from public, anon, authenticated;
revoke all on function public.monzo_worker_finish(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.monzo_worker_connections() to service_role;
grant execute on function public.monzo_worker_lease(uuid, uuid, integer) to service_role;
grant execute on function public.monzo_worker_release(uuid, uuid, text) to service_role;
grant execute on function public.monzo_worker_save_tokens(uuid, uuid, text, text, timestamptz) to service_role;
grant execute on function public.monzo_store_initial_tokens(text, text, text, timestamptz) to service_role;
grant execute on function public.monzo_worker_claim(uuid, uuid, integer) to service_role;
grant execute on function public.monzo_worker_finish(uuid, text, text, text) to service_role;
revoke all on function public.list_monzo_pot_transfers(uuid) from public, anon;
grant execute on function public.list_monzo_pot_transfers(uuid) to authenticated;

-- Payments already applied (e.g. the first live test) get a dry_run row, so they can never be
-- transferred later.
insert into public.monzo_pot_transfers (monzo_payment_id, connection_id, monzo_transaction_id, pot_id, amount_pence,
                                        status, dedupe_id, release_at)
select m.id, c.id, m.monzo_transaction_id, c.pot_id, m.amount_pence - m.leftover_pence, 'dry_run',
       'fpa-pot-' || m.id::text, now()
  from public.monzo_payments m
  join public.monzo_connections c on c.team_id = m.team_id and c.active
 where m.status = 'applied' and m.amount_pence - m.leftover_pence > 0
on conflict (monzo_payment_id) do nothing;
