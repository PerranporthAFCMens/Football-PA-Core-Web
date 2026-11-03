-- Monzo matching: recognise the app's own multi-game payment link reference "<PlayerName>Subs"
-- (e.g. "DanGilbertSubs", built by get_subs_tracker_v2). Replaces record_monzo_payment only.
-- Rollback: re-run record_monzo_payment from 20261103221500_monzo_short_name_match.sql.

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

  -- 2b. The payment reference contains exactly one current player's full name
  --     (payment links from the app put the player's name in the reference, and a parent
  --     paying for a player usually writes the player's name).
  if v_player is null and v_ref is not null then
    select count(distinct p.id), min(p.id::text)::uuid into v_count, v_player
      from public.team_players tp join public.players p on p.id = tp.player_id
     where tp.team_id = conn.team_id and tp.active
       and exists (select 1 from unnest(array[public.monzo_normalise_name(p.display_name),
                                              public.monzo_normalise_name(concat_ws(' ', p.first_name, p.last_name))]) n(v)
                    where n.v ~ ' ' and (' ' || public.monzo_normalise_name(v_ref) || ' ' like '% ' || n.v || ' %'
                           -- the app's own player link: "<PlayerName>Subs", e.g. "DanGilbertSubs"
                           or lower(regexp_replace(v_ref, '[^A-Za-z0-9]', '', 'g'))
                              like '%' || replace(n.v, ' ', '') || 'subs%'));
    if v_count = 1 then v_method := 'reference'; else v_player := null; end if;
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

  -- 4. Short and long first names with the same surname ("DANIEL GILBERT" <-> Dan Gilbert,
  --    "TOM SMITH" <-> Thomas Smith). Uses the first and last word of the account name, and
  --    only matches if exactly one player fits.
  if v_player is null and v_norm ~ ' ' then
    select count(distinct p.id), min(p.id::text)::uuid into v_count, v_player
      from public.team_players tp join public.players p on p.id = tp.player_id
      cross join lateral (select split_part(public.monzo_normalise_name(coalesce(p.first_name, split_part(p.display_name, ' ', 1))), ' ', 1) as fn,
                                 public.monzo_normalise_name(coalesce(p.last_name, regexp_replace(p.display_name, '^.* ', ''))) as ln) n
     where tp.team_id = conn.team_id and tp.active
       and length(n.fn) >= 2 and length(split_part(v_norm, ' ', 1)) >= 2
       and n.ln = regexp_replace(v_norm, '^.* ', '')
       and (n.fn like split_part(v_norm, ' ', 1) || '%' or split_part(v_norm, ' ', 1) like n.fn || '%');
    if v_count = 1 then v_method := 'short_name'; else v_player := null; end if;
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

