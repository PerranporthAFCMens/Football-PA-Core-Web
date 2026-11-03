-- Monzo payments into the Subs Tracker.
-- Monzo sends a webhook for every new transaction on the connected account. The monzo-webhook
-- edge function passes incoming GBP payments to record_monzo_payment(), which works out which
-- player paid and queues the payment on the Subs Tracker. A manager then taps Apply, which marks
-- the player's oldest unpaid games as paid using the existing set_subs_match_status RPC.
--
-- Players who pay from an account in someone else's name are handled by monzo_payer_aliases:
-- the first time, the payment lands in "Needs a player"; the manager picks the player and ticks
-- "Remember this payer", and later payments from that account match automatically.
--
-- Additive only: three new tables and new functions. Nothing existing is changed.
-- Rollback: drop the six functions below, then drop tables monzo_payments, monzo_payer_aliases,
-- monzo_connections.

create table if not exists public.monzo_connections (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  monzo_account_id text not null unique,
  webhook_secret text not null default encode(extensions.gen_random_bytes(24), 'hex'),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.monzo_payer_aliases (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  -- 'monzo:<user id>', 'acct:<sort code>:<account number>' or 'name:<normalised name>'
  match_key text not null,
  label text,
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (team_id, match_key)
);

create table if not exists public.monzo_payments (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  monzo_transaction_id text not null unique,
  amount_pence integer not null check (amount_pence > 0),
  payer_name text,
  payer_keys text[] not null default '{}',
  reference text,
  received_at timestamptz not null,
  player_id uuid references public.players(id) on delete set null,
  match_method text,           -- 'alias', 'name', 'initial_surname', 'manual'
  status text not null default 'unmatched' check (status in ('unmatched', 'matched', 'applied', 'ignored')),
  applied_fixture_ids uuid[] not null default '{}',
  leftover_pence integer not null default 0,
  handled_by uuid,
  handled_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists monzo_payments_team_status_idx on public.monzo_payments (team_id, status, received_at desc);

alter table public.monzo_connections enable row level security;
alter table public.monzo_payer_aliases enable row level security;
alter table public.monzo_payments enable row level security;
-- No direct table access. Everything goes through the functions below.
revoke all on public.monzo_connections, public.monzo_payer_aliases, public.monzo_payments from public, anon, authenticated;

-- Lower case, letters and spaces only, titles removed: "MR J. O'NEILL" -> "j oneill"
create or replace function public.monzo_normalise_name(p text)
 returns text language sql immutable set search_path to 'public'
as $function$
  select nullif(btrim(regexp_replace(
    regexp_replace(
      regexp_replace(lower(coalesce(p, '')), '[^a-z ]', '', 'g'),
      '^(mr|mrs|ms|miss|mx|dr) ', ''),
    '\s+', ' ', 'g')), '');
$function$;

-- Called only by the monzo-webhook edge function (service role).
-- p_tx is the "data" object of a Monzo transaction.created webhook.
create or replace function public.record_monzo_payment(p_secret text, p_tx jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  conn public.monzo_connections;
  v_amount integer := coalesce((p_tx->>'amount')::integer, 0);
  v_cp jsonb := coalesce(p_tx->'counterparty', '{}'::jsonb);
  v_name text := nullif(btrim(coalesce(v_cp->>'name', v_cp->>'preferred_name', '')), '');
  v_norm text;
  v_keys text[] := '{}';
  v_ref text := nullif(btrim(concat_ws(' ', nullif(p_tx->>'description', ''), nullif(p_tx->>'notes', ''))), '');
  v_charge integer;
  v_player uuid;
  v_method text;
  v_count integer;
  v_id uuid;
begin
  select * into conn from public.monzo_connections
   where monzo_account_id = p_tx->>'account_id' and active;
  if conn.id is null or conn.webhook_secret is distinct from p_secret then
    return jsonb_build_object('ok', false, 'reason', 'unknown_account');
  end if;

  -- Money in, in pounds, and not a pot transfer or top-up.
  if v_amount <= 0 or coalesce(p_tx->>'currency', '') <> 'GBP'
     or coalesce((p_tx->>'is_load')::boolean, false)
     or coalesce(p_tx->>'scheme', '') = 'uk_retail_pot' then
    return jsonb_build_object('ok', true, 'skipped', 'not_incoming_payment');
  end if;

  if exists (select 1 from public.monzo_payments where monzo_transaction_id = p_tx->>'id') then
    return jsonb_build_object('ok', true, 'skipped', 'duplicate');
  end if;

  v_norm := public.monzo_normalise_name(v_name);
  if nullif(v_cp->>'user_id', '') is not null then v_keys := v_keys || ('monzo:' || (v_cp->>'user_id')); end if;
  if nullif(v_cp->>'account_number', '') is not null then
    v_keys := v_keys || ('acct:' || regexp_replace(coalesce(v_cp->>'sort_code', ''), '\D', '', 'g') || ':' || regexp_replace(v_cp->>'account_number', '\D', '', 'g'));
  end if;
  if v_norm is not null then v_keys := v_keys || ('name:' || v_norm); end if;

  -- 1. A remembered payer (account first, then name).
  select a.player_id into v_player
    from public.monzo_payer_aliases a
   where a.team_id = conn.team_id and a.match_key = any(v_keys)
   order by (a.match_key like 'name:%'), a.created_at desc
   limit 1;
  if v_player is not null then v_method := 'alias'; end if;

  -- 2. The account name is exactly one current player's name.
  if v_player is null and v_norm is not null then
    select count(distinct p.id), min(p.id::text)::uuid into v_count, v_player
      from public.team_players tp join public.players p on p.id = tp.player_id
     where tp.team_id = conn.team_id and tp.active
       and (public.monzo_normalise_name(p.display_name) = v_norm
            or public.monzo_normalise_name(concat_ws(' ', p.first_name, p.last_name)) = v_norm);
    if v_count = 1 then v_method := 'name'; else v_player := null; end if;
  end if;

  -- 3. "J SMITH" style: first initial + surname, only if exactly one player fits.
  if v_player is null and v_norm ~ '^[a-z] [a-z]' then
    select count(distinct p.id), min(p.id::text)::uuid into v_count, v_player
      from public.team_players tp join public.players p on p.id = tp.player_id
     where tp.team_id = conn.team_id and tp.active
       and p.first_name is not null and p.last_name is not null
       and left(public.monzo_normalise_name(p.first_name), 1) = left(v_norm, 1)
       and public.monzo_normalise_name(p.last_name) = substr(v_norm, 3);
    if v_count = 1 then v_method := 'initial_surname'; else v_player := null; end if;
  end if;

  -- Personal accounts receive other money too. Only keep an unknown payer's payment if it looks
  -- like subs: a whole number of games, or "sub" in the reference. Anything else is not stored.
  if v_player is null then
    select s.amount_pence into v_charge from public.subs_settings s
     where s.team_id = conn.team_id and s.active order by s.updated_at desc limit 1;
    if not (coalesce(v_ref, '') ~* 'sub'
            or (coalesce(v_charge, 0) > 0 and v_amount % v_charge = 0 and v_amount / v_charge <= 10)) then
      return jsonb_build_object('ok', true, 'skipped', 'not_subs');
    end if;
  end if;

  insert into public.monzo_payments (club_id, team_id, monzo_transaction_id, amount_pence, payer_name, payer_keys,
                                     reference, received_at, player_id, match_method, status)
  values (conn.club_id, conn.team_id, p_tx->>'id', v_amount, v_name, v_keys, v_ref,
          coalesce((p_tx->>'created')::timestamptz, now()), v_player, v_method,
          case when v_player is null then 'unmatched' else 'matched' end)
  on conflict (monzo_transaction_id) do nothing
  returning id into v_id;

  return jsonb_build_object('ok', true, 'payment_id', v_id, 'matched', v_player is not null, 'method', v_method);
end;
$function$;

-- Subs Tracker: payments waiting for a player or for Apply, plus the last 20 handled, plus remembered payers.
create or replace function public.list_monzo_payments(p_team_id uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_manage_subs(p_team_id) then raise exception 'You do not have permission to manage subs'; end if;
  return jsonb_build_object(
    'connected', exists (select 1 from public.monzo_connections where team_id = p_team_id and active),
    'pending', coalesce((select jsonb_agg(row_to_json(x) order by x.received_at) from (
        select m.id, m.amount_pence, m.payer_name, m.reference, m.received_at, m.player_id, m.match_method, m.status,
               p.display_name as player_name
          from public.monzo_payments m left join public.players p on p.id = m.player_id
         where m.team_id = p_team_id and m.status in ('unmatched', 'matched')) x), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(row_to_json(x) order by x.handled_at desc) from (
        select m.id, m.amount_pence, m.payer_name, m.received_at, m.status, m.handled_at, m.leftover_pence,
               cardinality(m.applied_fixture_ids) as games, p.display_name as player_name
          from public.monzo_payments m left join public.players p on p.id = m.player_id
         where m.team_id = p_team_id and m.status in ('applied', 'ignored')
         order by m.handled_at desc limit 20) x), '[]'::jsonb),
    'aliases', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'label', a.label, 'player_id', a.player_id,
                                                            'player_name', p.display_name) order by p.display_name)
          from public.monzo_payer_aliases a join public.players p on p.id = a.player_id
         where a.team_id = p_team_id), '[]'::jsonb));
end;
$function$;

-- Manager picks the player for a payment. p_remember saves the payer so it matches automatically next time.
create or replace function public.assign_monzo_payment(p_payment_id uuid, p_player_id uuid, p_remember boolean default true)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare m public.monzo_payments; k text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into m from public.monzo_payments where id = p_payment_id;
  if m.id is null then raise exception 'Payment not found'; end if;
  if not public.can_manage_subs(m.team_id) then raise exception 'You do not have permission to manage subs'; end if;
  if m.status = 'applied' then raise exception 'This payment has already been applied'; end if;
  if not exists (select 1 from public.team_players where team_id = m.team_id and player_id = p_player_id) then
    raise exception 'That player is not in this team';
  end if;
  update public.monzo_payments set player_id = p_player_id, match_method = 'manual', status = 'matched'
   where id = p_payment_id;
  if coalesce(p_remember, false) then
    foreach k in array m.payer_keys loop
      insert into public.monzo_payer_aliases (team_id, player_id, match_key, label, created_by)
      values (m.team_id, p_player_id, k, coalesce(m.payer_name, 'Unknown payer'), auth.uid())
      on conflict (team_id, match_key) do update set player_id = excluded.player_id, label = excluded.label;
    end loop;
  end if;
  return jsonb_build_object('ok', true);
end;
$function$;

-- Called by the Subs Tracker after it has marked the games paid (status 'applied'),
-- or when the manager says the payment is not subs (status 'ignored').
create or replace function public.finish_monzo_payment(p_payment_id uuid, p_status text,
                                                       p_fixture_ids uuid[] default '{}', p_leftover_pence integer default 0)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_team uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_status not in ('applied', 'ignored') then raise exception 'Invalid status'; end if;
  select team_id into v_team from public.monzo_payments where id = p_payment_id;
  if v_team is null then raise exception 'Payment not found'; end if;
  if not public.can_manage_subs(v_team) then raise exception 'You do not have permission to manage subs'; end if;
  update public.monzo_payments
     set status = p_status, applied_fixture_ids = coalesce(p_fixture_ids, '{}'),
         leftover_pence = greatest(coalesce(p_leftover_pence, 0), 0), handled_by = auth.uid(), handled_at = now()
   where id = p_payment_id and status in ('unmatched', 'matched');
  if not found then raise exception 'This payment has already been handled'; end if;
  return jsonb_build_object('ok', true);
end;
$function$;

create or replace function public.remove_monzo_payer_alias(p_alias_id uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_team uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select team_id into v_team from public.monzo_payer_aliases where id = p_alias_id;
  if v_team is null then raise exception 'Remembered payer not found'; end if;
  if not public.can_manage_subs(v_team) then raise exception 'You do not have permission to manage subs'; end if;
  delete from public.monzo_payer_aliases where id = p_alias_id;
  return jsonb_build_object('ok', true);
end;
$function$;

revoke all on function public.monzo_normalise_name(text) from public, anon, authenticated;
revoke all on function public.record_monzo_payment(text, jsonb) from public, anon, authenticated;
grant execute on function public.record_monzo_payment(text, jsonb) to service_role;
revoke all on function public.list_monzo_payments(uuid) from public, anon;
revoke all on function public.assign_monzo_payment(uuid, uuid, boolean) from public, anon;
revoke all on function public.finish_monzo_payment(uuid, text, uuid[], integer) from public, anon;
revoke all on function public.remove_monzo_payer_alias(uuid) from public, anon;
grant execute on function public.list_monzo_payments(uuid) to authenticated;
grant execute on function public.assign_monzo_payment(uuid, uuid, boolean) to authenticated;
grant execute on function public.finish_monzo_payment(uuid, text, uuid[], integer) to authenticated;
grant execute on function public.remove_monzo_payer_alias(uuid) to authenticated;
