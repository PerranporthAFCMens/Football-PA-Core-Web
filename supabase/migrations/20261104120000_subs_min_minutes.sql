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
      -- Leave it alone if a manager set a status or the game is already paid.
      if not exists (select 1 from public.subs_fixture_statuses st where st.fixture_id = p_fixture_id and st.player_id = p.player_id)
         and not exists (select 1 from public.subs_payments sp where sp.fixture_id = p_fixture_id and sp.player_id = p.player_id) then
        insert into public.subs_fixture_statuses (club_id, team_id, season_id, fixture_id, player_id, status, note)
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

-- Finished matches in each team's current subs season (games already paid or with a status are skipped).
select f.id, public.apply_subs_min_minutes(f.id) as auto_na
  from public.fixtures f
  join public.subs_settings s on s.team_id = f.team_id and s.active and s.season_id = f.season_id
 where lower(coalesce(f.status, '')) in ('ft','full_time','completed','complete','finished');
