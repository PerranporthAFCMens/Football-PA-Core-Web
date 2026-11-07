-- Credit ledger: positive = received credit, negative = credit spent on a fixture.
-- Do not grant direct reads to portal clients; use scoped, authenticated RPCs.
create table if not exists public.subs_credit_ledger (
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null, team_id uuid not null, season_id uuid not null,
 player_id uuid not null, fixture_id uuid,
 origin_payment_id uuid unique, usage_fixture_id uuid,
 amount_pence integer not null check (amount_pence <> 0),
 note text not null, created_at timestamptz not null default now(),
 constraint credit_direction check (
   (amount_pence > 0 and origin_payment_id is not null and usage_fixture_id is null)
   or (amount_pence < 0 and origin_payment_id is null and usage_fixture_id is not null))
);
create unique index if not exists subs_credit_spent_once
 on public.subs_credit_ledger(team_id,player_id,usage_fixture_id)
 where usage_fixture_id is not null;
create index if not exists subs_credit_player_idx
 on public.subs_credit_ledger(team_id,player_id,created_at);
alter table public.subs_credit_ledger enable row level security;
revoke all on public.subs_credit_ledger from public,anon,authenticated;

create or replace function public.apply_subs_credit(p_team_id uuid,p_player_id uuid)
returns integer language plpgsql security definer set search_path='public'
as $fn$
declare
 v_balance integer; v_amount integer; v_club uuid; v_season uuid;
 v_fx record; v_applied integer:=0;
begin
 perform pg_advisory_xact_lock(hashtext(p_team_id::text),hashtext(p_player_id::text));
 select coalesce(sum(amount_pence),0)::int into v_balance
 from public.subs_credit_ledger where team_id=p_team_id and player_id=p_player_id;
 if v_balance<=0 then return 0; end if;
 select s.amount_pence,s.season_id,s.club_id into v_amount,v_season,v_club
 from public.subs_settings s where s.team_id=p_team_id and s.active
 order by s.updated_at desc limit 1;
 if coalesce(v_amount,0)<=0 then return 0; end if;
 for v_fx in
   select f.id,f.opponent,f.kick_off from public.fixtures f
   where f.team_id=p_team_id and f.season_id=v_season
     and lower(coalesce(f.status,''))<>'cancelled'
     and not exists (select 1 from public.subs_payments sp
                     where sp.fixture_id=f.id and sp.player_id=p_player_id)
     and not exists (select 1 from public.subs_fixture_statuses st
                     where st.fixture_id=f.id and st.player_id=p_player_id
                       and st.status in ('na','claimed_paid'))
     and (
       (lower(coalesce(f.status,'')) in ('ft','full_time','completed','complete','finished')
         and (exists(select 1 from public.match_lineups ml where ml.fixture_id=f.id and ml.player_id=p_player_id and ml.starter)
             or exists(select 1 from public.substitutions su where su.fixture_id=f.id and su.player_on_id=p_player_id)))
       or
       (lower(coalesce(f.status,'')) not in ('ft','full_time','completed','complete','finished')
         and exists(select 1 from public.match_squads ms where ms.fixture_id=f.id and ms.player_id=p_player_id and ms.selected))
       or exists(select 1 from public.subs_fixture_statuses st
                 where st.fixture_id=f.id and st.player_id=p_player_id and st.status='not_paid')
     )
   order by f.kick_off nulls last,f.id
 loop
   exit when v_balance<v_amount;
   -- Pay only one charge per match. A previous payment or ledger debit blocks a repeat.
   if exists(select 1 from public.subs_credit_ledger l where l.team_id=p_team_id
      and l.player_id=p_player_id and l.usage_fixture_id=v_fx.id) then continue; end if;
   insert into public.subs_credit_ledger
     (club_id,team_id,season_id,player_id,fixture_id,usage_fixture_id,amount_pence,note)
   values(v_club,p_team_id,v_season,p_player_id,v_fx.id,v_fx.id,-v_amount,
          'Credit used: '||v_fx.opponent);
   delete from public.subs_fixture_statuses
    where fixture_id=v_fx.id and player_id=p_player_id and status='not_paid';
   insert into public.subs_payments
    (club_id,team_id,season_id,fixture_id,player_id,amount_pence,method,note,paid_at)
   values(v_club,p_team_id,v_season,v_fx.id,p_player_id,v_amount,'Credit',
          'Paid from existing player credit for '||v_fx.opponent,now());
   v_balance:=v_balance-v_amount; v_applied:=v_applied+1;
 end loop;
 return v_applied;
end;
$fn$;
revoke all on function public.apply_subs_credit(uuid,uuid) from public,anon,authenticated;

-- Subs: a player who was on the pitch for less than 20 minutes in a finished match pays no subs for it.
-- Minutes are counted the same way as the player dashboard: a starter is on from 0, a sub from the
-- minute they came on; they go off at a substitution or a red card; anyone still on plays to the end
-- (period_count x period_minutes from team_settings). Stoppage time is not counted.
--
-- When a match is finished (or its lineup, subs or red cards change after it finished), each player who appeared
-- with fewer minutes than the team's limit is marked N/A on the Subs Tracker, unless a manager has
-- already set a status or the game is already paid. If later edits take them to 20+ minutes, the
-- automatic N/A is removed again. A manager can still change any of these on the Subs Tracker.
--
-- Additive: one column (subs_settings.min_minutes, default 20; 0 turns it off), three functions,
-- four triggers, and a one-off run for this season's finished matches.
-- Rollback: drop triggers subs_min_minutes_fixture on public.fixtures, subs_min_minutes_lineups on
-- public.match_lineups, subs_min_minutes_subs on public.substitutions, subs_min_minutes_events on
-- public.match_events; drop functions
-- public.subs_min_minutes_trg(), public.apply_subs_min_minutes(uuid), public.subs_minutes_played(uuid, uuid);
-- delete from public.subs_fixture_statuses where note = 'Auto: under minimum minutes';
-- alter table public.subs_settings drop column min_minutes.

alter table public.subs_settings add column if not exists min_minutes integer not null default 20
  check (min_minutes between 0 and 200);

-- Minutes a player was on the pitch in one match (null if they did not appear).
create or replace function public.subs_minutes_played(p_fixture_id uuid, p_player_id uuid)
 returns integer language plpgsql stable security definer set search_path to 'public'
as $function$
declare
  v_total integer;
  v_active boolean;
  v_on integer;
  v_mins integer := 0;
  v_appeared boolean;
  e record;
begin
  select greatest(1, coalesce(ts.period_count, 2) * coalesce(ts.period_minutes, 45)) into v_total
    from public.fixtures f left join public.team_settings ts on ts.team_id = f.team_id
   where f.id = p_fixture_id;
  if v_total is null then return null; end if;

  v_active := exists (select 1 from public.match_lineups ml
                       where ml.fixture_id = p_fixture_id and ml.player_id = p_player_id and ml.starter);
  v_appeared := v_active or exists (select 1 from public.substitutions s
                                     where s.fixture_id = p_fixture_id and s.player_on_id = p_player_id);
  if not v_appeared then return null; end if;
  v_on := case when v_active then 0 end;

  for e in
    select kind, least(v_total, greatest(0, minute)) as minute from (
      select case when s.player_off_id = p_player_id then 'off' else 'on' end as kind,
             coalesce(s.minute, 0) as minute, coalesce(s.stoppage_minute, 0) as stoppage, s.created_at
        from public.substitutions s
       where s.fixture_id = p_fixture_id and (s.player_on_id = p_player_id or s.player_off_id = p_player_id)
      union all
      select 'off', coalesce(me.minute, 0), coalesce(me.stoppage_minute, 0), me.created_at
        from public.match_events me
       where me.fixture_id = p_fixture_id and me.player_id = p_player_id
         and lower(coalesce(me.event_type, '')) in ('red', 'red_card')
    ) x
    order by x.minute, x.stoppage, x.created_at
  loop
    if e.kind = 'off' and v_active then
      v_mins := v_mins + greatest(0, e.minute - v_on); v_active := false; v_on := null;
    elsif e.kind = 'on' and not v_active then
      v_active := true; v_on := e.minute;
    end if;
  end loop;
  if v_active then v_mins := v_mins + greatest(0, v_total - v_on); end if;
  return v_mins;
end;
$function$;

-- Mark (or unmark) automatic N/A for one finished match. Returns how many players are auto N/A.
create or replace function public.apply_subs_min_minutes(p_fixture_id uuid)
 returns integer language plpgsql security definer set search_path to 'public'
as $function$
declare
  f public.fixtures;
  v_club uuid;
  v_min integer;
  v_count integer := 0;
  p record;
  v_pay record;
begin
  select * into f from public.fixtures where id = p_fixture_id;
  if f.id is null or f.season_id is null then return 0; end if;
  if lower(coalesce(f.status, '')) not in ('ft','full_time','completed','complete','finished') then return 0; end if;
  select t.club_id into v_club from public.teams t where t.id = f.team_id;
  select coalesce(s.min_minutes, 20) into v_min from public.subs_settings s
   where s.team_id = f.team_id and s.active order by s.updated_at desc limit 1;
  v_min := coalesce(v_min, 20);

  for p in
    select x.player_id, public.subs_minutes_played(p_fixture_id, x.player_id) as mins
      from (select ml.player_id from public.match_lineups ml where ml.fixture_id = p_fixture_id and ml.starter
            union select s.player_on_id from public.substitutions s where s.fixture_id = p_fixture_id and s.player_on_id is not null
            union select st.player_id from public.subs_fixture_statuses st
                   where st.fixture_id = p_fixture_id and st.note = 'Auto: under minimum minutes') x
  loop
    if p.mins is not null and p.mins < v_min then
      -- A prepaid appearance below the limit becomes a real, auditable
      -- player credit. Never initiate a Monzo refund or a new transfer.
      for v_pay in
        select sp.* from public.subs_payments sp
        where sp.fixture_id=p_fixture_id and sp.player_id=p.player_id
        for update
      loop
        if v_pay.method='Credit' then
          -- The player did not owe for this match. Undo the previously
          -- spent credit so it becomes available again.
          delete from public.subs_payments where id=v_pay.id;
          delete from public.subs_credit_ledger
            where team_id=f.team_id and player_id=p.player_id
              and usage_fixture_id=p_fixture_id;
        else
          insert into public.subs_credit_ledger
            (club_id,team_id,season_id,player_id,fixture_id,origin_payment_id,amount_pence,note)
          values (v_pay.club_id,v_pay.team_id,v_pay.season_id,v_pay.player_id,p_fixture_id,
                  v_pay.id,v_pay.amount_pence,'No subs: under '||v_min||' minutes')
          on conflict (origin_payment_id) do nothing;
          delete from public.subs_payments where id=v_pay.id;
        end if;
      end loop;
      if not exists (select 1 from public.subs_fixture_statuses st
                     where st.fixture_id=p_fixture_id and st.player_id=p.player_id)
         and not exists (select 1 from public.subs_payments sp
                         where sp.fixture_id=p_fixture_id and sp.player_id=p.player_id)
      then
        insert into public.subs_fixture_statuses (club_id,team_id,season_id,fixture_id,player_id,status,note)
        values (v_club, f.team_id, f.season_id, p_fixture_id, p.player_id, 'na', 'Auto: under minimum minutes');
      end if;
      if exists (select 1 from public.subs_fixture_statuses st where st.fixture_id = p_fixture_id
                  and st.player_id = p.player_id and st.note = 'Auto: under minimum minutes') then
        v_count := v_count + 1;
      end if;
    else
      -- Now 20+ minutes (or no longer appeared): remove only our own automatic N/A.
      delete from public.subs_fixture_statuses st
       where st.fixture_id = p_fixture_id and st.player_id = p.player_id
         and st.status = 'na' and st.note = 'Auto: under minimum minutes';
    end if;
    perform public.apply_subs_credit(f.team_id,p.player_id);
  end loop;
  return v_count;
end;
$function$;

create or replace function public.subs_min_minutes_trg()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare v_fixture uuid;
begin
  begin
    if tg_table_name = 'fixtures' then
      v_fixture := new.id;
    elsif tg_op = 'DELETE' then
      v_fixture := old.fixture_id;
    else
      v_fixture := new.fixture_id;
    end if;
    perform public.apply_subs_min_minutes(v_fixture);
  exception when others then
    -- Never block saving a match because of subs.
    raise warning 'apply_subs_min_minutes failed for %: %', v_fixture, sqlerrm;
  end;
  return null;
end;
$function$;

drop trigger if exists subs_min_minutes_fixture on public.fixtures;
create trigger subs_min_minutes_fixture
  after update of status on public.fixtures
  for each row when (new.status is distinct from old.status)
  execute function public.subs_min_minutes_trg();

drop trigger if exists subs_min_minutes_lineups on public.match_lineups;
create trigger subs_min_minutes_lineups
  after insert or update or delete on public.match_lineups
  for each row execute function public.subs_min_minutes_trg();

drop trigger if exists subs_min_minutes_subs on public.substitutions;
create trigger subs_min_minutes_subs
  after insert or update or delete on public.substitutions
  for each row execute function public.subs_min_minutes_trg();

drop trigger if exists subs_min_minutes_events on public.match_events;
create trigger subs_min_minutes_events
  after insert or update or delete on public.match_events
  for each row execute function public.subs_min_minutes_trg();

revoke all on function public.subs_minutes_played(uuid, uuid) from public, anon, authenticated;
revoke all on function public.apply_subs_min_minutes(uuid) from public, anon, authenticated;
revoke all on function public.subs_min_minutes_trg() from public, anon, authenticated;



-- Apply saved credit to a newly selected match, including upcoming squads.
create or replace function public.subs_credit_squad_trg()
returns trigger language plpgsql security definer set search_path='public'
as $fn$
declare v_team uuid;
begin
 if new.selected then
   select team_id into v_team from public.fixtures where id=new.fixture_id;
   if v_team is not null then perform public.apply_subs_credit(v_team,new.player_id); end if;
 end if;
 return new;
end;
$fn$;
drop trigger if exists subs_credit_squad on public.match_squads;
create trigger subs_credit_squad after insert or update of selected on public.match_squads
 for each row execute function public.subs_credit_squad_trg();
revoke all on function public.subs_credit_squad_trg() from public,anon,authenticated;

-- If a manager undoes a credit-paid match, restore that credit rather
-- than silently losing it. Never generate new Monzo transfers.
create or replace function public.subs_credit_payment_undo_trg()
returns trigger language plpgsql security definer set search_path='public'
as $fn$
begin
 if old.method='Credit' and old.fixture_id is not null then
   delete from public.subs_credit_ledger
   where team_id=old.team_id and player_id=old.player_id
     and usage_fixture_id=old.fixture_id;
 end if;
 return old;
end;
$fn$;
drop trigger if exists subs_credit_payment_undo on public.subs_payments;
create trigger subs_credit_payment_undo after delete on public.subs_payments
 for each row execute function public.subs_credit_payment_undo_trg();
revoke all on function public.subs_credit_payment_undo_trg() from public,anon,authenticated;

-- Financial snapshot uses actual paid fixtures and official status N/A,
-- rather than charging every appearance like the old portal.
create or replace function public.subs_player_credit_snapshot(p_team uuid,p_player uuid)
returns jsonb language plpgsql stable security definer set search_path='public'
as $fn$
declare v_cfg public.subs_settings%rowtype; v_balance integer; v_due integer;
 v_paid integer; v_events jsonb; v_link text;
begin
 select * into v_cfg from public.subs_settings
 where team_id=p_team and active order by updated_at desc limit 1;
 if v_cfg.id is null then return jsonb_build_object('credit_pence',0,'outstanding_pence',0,'events','[]'::jsonb); end if;
 select coalesce(sum(amount_pence),0)::int into v_balance
 from public.subs_credit_ledger where team_id=p_team and player_id=p_player;
 select coalesce(sum(amount_pence),0)::int into v_paid
 from public.subs_payments where team_id=p_team and season_id=v_cfg.season_id and player_id=p_player;
 select count(*)::int * v_cfg.amount_pence into v_due
 from public.fixtures f
 where f.team_id=p_team and f.season_id=v_cfg.season_id
   and lower(coalesce(f.status,''))<>'cancelled'
   and not exists(select 1 from public.subs_payments sp where sp.fixture_id=f.id and sp.player_id=p_player)
   and not exists(select 1 from public.subs_fixture_statuses st where st.fixture_id=f.id
     and st.player_id=p_player and st.status in ('na','claimed_paid'))
   and (
     (lower(coalesce(f.status,'')) in ('ft','full_time','completed','complete','finished') and
       (exists(select 1 from public.match_lineups ml where ml.fixture_id=f.id and ml.player_id=p_player and ml.starter)
        or exists(select 1 from public.substitutions su where su.fixture_id=f.id and su.player_on_id=p_player)))
     or (lower(coalesce(f.status,'')) not in ('ft','full_time','completed','complete','finished') and
        exists(select 1 from public.match_squads ms where ms.fixture_id=f.id and ms.player_id=p_player and ms.selected))
     or exists(select 1 from public.subs_fixture_statuses st where st.fixture_id=f.id and st.player_id=p_player and st.status='not_paid')
   );
 select coalesce(jsonb_agg(jsonb_build_object('amount_pence',l.amount_pence,'note',l.note,
 'created_at',l.created_at,'opponent',f.opponent) order by l.created_at desc),'[]'::jsonb)
 into v_events from (select * from public.subs_credit_ledger
 where team_id=p_team and player_id=p_player order by created_at desc limit 30) l
 left join public.fixtures f on f.id=l.fixture_id;
 if greatest(0,v_due-v_balance)>0 and coalesce(v_cfg.payment_url_template,'')<>'' then
   v_link:=replace(v_cfg.payment_url_template,'{amount}',
        to_char(greatest(0,v_due-v_balance)/100.0,'FM999999990.00'));
   v_link:=replace(v_link,'{reference}',
        coalesce((select regexp_replace(display_name,'[^A-Za-z0-9]','','g') from public.players where id=p_player),'Player')||'Subs');
 end if;
 return jsonb_build_object('credit_pence',greatest(0,v_balance),'outstanding_pence',greatest(0,v_due-v_balance),
  'amount_due_pence',v_due,'amount_paid_pence',v_paid,'payment_link',v_link,'events',v_events);
end;
$fn$;
revoke all on function public.subs_player_credit_snapshot(uuid,uuid) from public,anon,authenticated;

create or replace function public.list_subs_player_credits(p_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='public'
as $fn$
begin
 if auth.uid() is null or not public.can_manage_subs(p_team_id) then raise exception 'Subs permission required'; end if;
 return jsonb_build_object(
   'players',coalesce((select jsonb_agg(jsonb_build_object('player_id',p.id,'account',
     public.subs_player_credit_snapshot(p_team_id,p.id)) order by p.display_name)
     from public.team_players tp join public.players p on p.id=tp.player_id
     where tp.team_id=p_team_id and tp.active),'[]'::jsonb),
   'cash_received_pence',
      coalesce((select sum(sp.amount_pence) from public.subs_payments sp
         where sp.team_id=p_team_id and sp.method is distinct from 'Credit'
         and sp.season_id=(select season_id from public.subs_settings where team_id=p_team_id and active order by updated_at desc limit 1)),0)
      + coalesce((select sum(l.amount_pence) from public.subs_credit_ledger l
         where l.team_id=p_team_id and l.origin_payment_id is not null
         and l.season_id=(select season_id from public.subs_settings where team_id=p_team_id and active order by updated_at desc limit 1)),0)
 );
end;
$fn$;
revoke all on function public.list_subs_player_credits(uuid) from public,anon,authenticated;
grant execute on function public.list_subs_player_credits(uuid) to authenticated;

create or replace function public.player_portal_subs_credit(p_token text)
returns jsonb language plpgsql stable security definer set search_path='public','extensions'
as $fn$
declare v_team uuid;v_player uuid;
begin
 select s.team_id,s.player_id into v_team,v_player from public.player_portal_sessions s
 where s.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
 and s.expires_at>now();
 if v_player is null then raise exception 'Player session expired';end if;
 return public.subs_player_credit_snapshot(v_team,v_player);
end;
$fn$;
revoke all on function public.player_portal_subs_credit(text) from public,anon,authenticated;
grant execute on function public.player_portal_subs_credit(text) to anon,authenticated;

create or replace function public.get_my_subs_credit()
returns jsonb language plpgsql stable security definer set search_path='public'
as $fn$
declare v_team uuid;v_player uuid;
begin
 if auth.uid() is null then raise exception 'Not signed in';end if;
 select team_id,player_id into v_team,v_player from public.team_memberships
 where user_id=auth.uid() and active and player_id is not null order by updated_at desc limit 1;
 if v_player is null then raise exception 'Player not linked';end if;
 return public.subs_player_credit_snapshot(v_team,v_player);
end;
$fn$;
revoke all on function public.get_my_subs_credit() from public,anon,authenticated;
grant execute on function public.get_my_subs_credit() to authenticated;
