-- Monzo payments mark games paid automatically.
-- As soon as a Monzo payment is matched to a player (by the webhook, or by a manager picking the
-- player), it is applied: one game per subs charge, written exactly the way the Subs Tracker's
-- "Received" button writes it (a subs_payments row for the fixture, any explicit status cleared).
--
-- Which games:
--   1. The game named in the reference. App payment links use "<Opponent>Subs", e.g. "Porthleven2ndSubs".
--   2. Then the player's oldest unpaid games (same rules as get_subs_tracker_v2: played, saved squad,
--      or an explicit status, with no payment and not N/A).
--   3. Then upcoming games, earliest first.
-- If nothing can be applied (no charge set, less than one game's money, player not in this season,
-- or the game in the reference is already paid, which suggests a duplicate),
-- the payment stays "matched" and shows on the Subs Tracker for a manager to handle.
--
-- Additive: one new function and one trigger. Payments already matched are applied at the end.
-- Rollback: drop trigger monzo_payments_auto_apply on public.monzo_payments; drop function
-- public.monzo_payments_auto_apply_trg(); drop function public.apply_monzo_payment(uuid).
-- Games it marked paid can be undone on the Subs Tracker with "Undo paid" (method = 'Monzo').

create or replace function public.apply_monzo_payment(p_payment_id uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  m public.monzo_payments;
  v_season uuid;
  v_charge integer;
  v_games integer;
  v_ref text;
  v_ids uuid[] := '{}';
  v_fx record;
begin
  select * into m from public.monzo_payments where id = p_payment_id for update;
  if m.id is null or m.status <> 'matched' or m.player_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_matched');
  end if;

  select s.season_id, s.amount_pence into v_season, v_charge
    from public.subs_settings s
   where s.team_id = m.team_id and s.active
   order by s.updated_at desc limit 1;
  if coalesce(v_charge, 0) <= 0 then return jsonb_build_object('ok', false, 'reason', 'no_charge'); end if;

  v_games := m.amount_pence / v_charge;
  if v_games < 1 then return jsonb_build_object('ok', false, 'reason', 'less_than_one_game'); end if;

  if not exists (select 1 from public.team_players tp
                  where tp.team_id = m.team_id and tp.season_id = v_season and tp.player_id = m.player_id) then
    return jsonb_build_object('ok', false, 'reason', 'player_not_in_season');
  end if;

  v_ref := lower(regexp_replace(coalesce(m.reference, ''), '[^A-Za-z0-9]', '', 'g'));

  -- The reference names a game this player has already paid for (e.g. marked Received by hand):
  -- probably a duplicate, so leave it for a manager rather than paying a different game.
  if exists (select 1 from public.fixtures f
              join public.subs_payments sp on sp.fixture_id = f.id and sp.player_id = m.player_id
             where f.team_id = m.team_id and f.season_id = v_season
               and length(regexp_replace(lower(coalesce(f.opponent, '')), '[^a-z0-9]', '', 'g')) >= 3
               and v_ref like '%' || regexp_replace(lower(f.opponent), '[^a-z0-9]', '', 'g') || 'subs%')
     and not exists (select 1 from public.fixtures f
              where f.team_id = m.team_id and f.season_id = v_season
                and lower(coalesce(f.status, '')) <> 'cancelled'
                and length(regexp_replace(lower(coalesce(f.opponent, '')), '[^a-z0-9]', '', 'g')) >= 3
                and v_ref like '%' || regexp_replace(lower(f.opponent), '[^a-z0-9]', '', 'g') || 'subs%'
                and not exists (select 1 from public.subs_payments sp where sp.fixture_id = f.id and sp.player_id = m.player_id)) then
    return jsonb_build_object('ok', false, 'reason', 'reference_game_already_paid');
  end if;

  for v_fx in
    with fx as (
      select f.id, f.opponent, f.kick_off,
             lower(coalesce(f.status, '')) in ('ft','full_time','completed','complete','finished') as is_final
        from public.fixtures f
       where f.team_id = m.team_id and f.season_id = v_season
         and lower(coalesce(f.status, '')) <> 'cancelled'
    ),
    open_fx as (   -- games this player has not paid for and are not N/A
      select fx.* from fx
       where not exists (select 1 from public.subs_payments sp where sp.fixture_id = fx.id and sp.player_id = m.player_id)
         and not exists (select 1 from public.subs_fixture_statuses st
                          where st.fixture_id = fx.id and st.player_id = m.player_id and st.status = 'na')
    ),
    owed as (      -- same "pairs" as get_subs_tracker_v2
      select o.id from open_fx o
       where (o.is_final and (exists (select 1 from public.match_lineups ml where ml.fixture_id = o.id and ml.player_id = m.player_id and ml.starter)
                           or exists (select 1 from public.substitutions su where su.fixture_id = o.id and su.player_on_id = m.player_id)))
          or (not o.is_final and exists (select 1 from public.match_squads ms where ms.fixture_id = o.id and ms.player_id = m.player_id and ms.selected))
          or exists (select 1 from public.subs_fixture_statuses st where st.fixture_id = o.id and st.player_id = m.player_id)
    ),
    ranked as (
      select o.id, o.opponent,
             case
               when length(regexp_replace(lower(coalesce(o.opponent, '')), '[^a-z0-9]', '', 'g')) >= 3
                and v_ref like '%' || regexp_replace(lower(o.opponent), '[^a-z0-9]', '', 'g') || 'subs%' then 1
               when o.id in (select id from owed) then 2
               when o.kick_off >= now() then 3
             end as tier,
             abs(extract(epoch from (coalesce(o.kick_off, now()) - m.received_at))) as distance,
             o.kick_off
        from open_fx o
    )
    select r.id, r.opponent from ranked r
     where r.tier is not null
     order by r.tier, case when r.tier = 1 then r.distance end, r.kick_off nulls last
     limit v_games
  loop
    delete from public.subs_fixture_statuses where fixture_id = v_fx.id and player_id = m.player_id;
    insert into public.subs_payments (club_id, team_id, season_id, fixture_id, player_id, amount_pence, method, note, paid_at)
    values (m.club_id, m.team_id, v_season, v_fx.id, m.player_id, v_charge, 'Monzo',
            'Paid for ' || v_fx.opponent || ' (Monzo)', m.received_at);
    v_ids := v_ids || v_fx.id;
  end loop;

  if cardinality(v_ids) = 0 then return jsonb_build_object('ok', false, 'reason', 'no_games_to_pay'); end if;

  update public.monzo_payments
     set status = 'applied', applied_fixture_ids = v_ids,
         leftover_pence = m.amount_pence - cardinality(v_ids) * v_charge, handled_at = now()
   where id = m.id;
  return jsonb_build_object('ok', true, 'games', cardinality(v_ids));
end;
$function$;

create or replace function public.monzo_payments_auto_apply_trg()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  perform public.apply_monzo_payment(new.id);
  return null;
end;
$function$;

drop trigger if exists monzo_payments_auto_apply on public.monzo_payments;
create trigger monzo_payments_auto_apply
  after insert or update of status, player_id on public.monzo_payments
  for each row when (new.status = 'matched')
  execute function public.monzo_payments_auto_apply_trg();

revoke all on function public.apply_monzo_payment(uuid) from public, anon, authenticated;
revoke all on function public.monzo_payments_auto_apply_trg() from public, anon, authenticated;

-- Apply payments that were already matched before this change (e.g. the first live payment).
select public.apply_monzo_payment(id) from public.monzo_payments where status = 'matched';
