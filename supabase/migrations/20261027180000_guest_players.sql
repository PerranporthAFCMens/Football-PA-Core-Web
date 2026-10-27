-- Guest players: reserve/one-off players. They are not on the availability roster, have no Player Portal access,
-- and are only added to the squad of the games they play.
create table if not exists public.team_guest_players (
  team_id uuid not null references public.teams(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (team_id, player_id)
);
alter table public.team_guest_players enable row level security;
revoke all on public.team_guest_players from public, anon, authenticated;

create or replace function public.list_team_guests(p_team_id uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_manage_players(p_team_id) then raise exception 'You do not have permission to manage players'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('player_id', g.player_id, 'name', p.display_name) order by p.display_name)
    from public.team_guest_players g join public.players p on p.id = g.player_id
    where g.team_id = p_team_id and p.active), '[]'::jsonb);
end;
$function$;

create or replace function public.set_player_guest(p_team_id uuid, p_player_id uuid, p_guest boolean)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_manage_players(p_team_id) then raise exception 'You do not have permission to manage players'; end if;
  if coalesce(p_guest, false) then
    insert into public.team_guest_players(team_id, player_id) values (p_team_id, p_player_id) on conflict do nothing;
    begin
      perform public.set_player_portal_access(p_team_id, p_player_id, false);
    exception when others then null;
    end;
  else
    delete from public.team_guest_players where team_id = p_team_id and player_id = p_player_id;
  end if;
  return jsonb_build_object('ok', true, 'guest', coalesce(p_guest, false));
end;
$function$;

create or replace function public.add_guest_player(p_team_id uuid, p_first_name text, p_last_name text, p_season_id uuid default null)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_club uuid; v_first text := btrim(coalesce(p_first_name, '')); v_last text := btrim(coalesce(p_last_name, ''));
  v_name text; v_player uuid; v_tp uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_manage_players(p_team_id) then raise exception 'You do not have permission to manage players'; end if;
  if v_first = '' then raise exception 'Enter a first name'; end if;
  select t.club_id into v_club from public.teams t where t.id = p_team_id;
  if v_club is null then raise exception 'Team not found'; end if;
  v_name := btrim(v_first || ' ' || v_last);
  select p.id into v_player from public.players p
  where p.club_id = v_club and lower(coalesce(p.first_name, '')) = lower(v_first)
    and lower(coalesce(p.last_name, '')) = lower(v_last)
  order by p.active desc, p.created_at limit 1;
  if v_player is null then
    insert into public.players(club_id, first_name, last_name, display_name, active)
    values (v_club, v_first, nullif(v_last, ''), v_name, true) returning id into v_player;
  else
    update public.players set active = true, updated_at = now() where id = v_player;
  end if;
  select tp.id into v_tp from public.team_players tp
  where tp.team_id = p_team_id and tp.player_id = v_player and tp.season_id is not distinct from p_season_id limit 1;
  if v_tp is null then
    insert into public.team_players(team_id, player_id, season_id, active) values (p_team_id, v_player, p_season_id, true);
  else
    update public.team_players set active = true, updated_at = now() where id = v_tp;
  end if;
  insert into public.team_guest_players(team_id, player_id) values (p_team_id, v_player) on conflict do nothing;
  return jsonb_build_object('ok', true, 'player_id', v_player, 'name', v_name);
end;
$function$;

revoke all on function public.list_team_guests(uuid), public.set_player_guest(uuid, uuid, boolean),
  public.add_guest_player(uuid, text, text, uuid) from public, anon;
grant execute on function public.list_team_guests(uuid), public.set_player_guest(uuid, uuid, boolean),
  public.add_guest_player(uuid, text, text, uuid) to authenticated;

CREATE OR REPLACE FUNCTION private.build_team_availability(p_team_id uuid, p_season_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_result jsonb;
begin
  with roster as (
    select
      tp.player_id,
      tp.created_at as joined_at,
      p.display_name,
      p.shirt_number
    from public.team_players tp
    join public.players p on p.id=tp.player_id
    where tp.team_id=p_team_id
      and tp.active
      and p.active
      and (p_season_id is null or tp.season_id=p_season_id or tp.season_id is null)
      and not exists (select 1 from public.team_guest_players g where g.team_id=tp.team_id and g.player_id=tp.player_id)
  ),
  polls as (
    select
      ap.fixture_id,
      ap.opened_at,
      f.opponent,
      f.venue,
      f.competition,
      f.kick_off,
      f.status,
      f.ground_name,
      f.ground_address,
      f.ground_postcode,
      f.season_id,
      case
        when lower(coalesce(f.competition,''))='league' then (
          select count(*)::int
          from public.fixtures lf
          where lf.team_id=f.team_id
            and lf.season_id is not distinct from f.season_id
            and lower(coalesce(lf.competition,''))='league'
            and lf.kick_off<=f.kick_off
        )
        else null
      end as gameweek_number
    from public.fixture_availability_polls ap
    join public.fixtures f on f.id=ap.fixture_id
    where ap.team_id=p_team_id
      and (p_season_id is null or ap.season_id=p_season_id)
      and lower(coalesce(f.status,'')) not in ('cancelled','postponed')
  ),
  fixture_rows as (
    select
      po.*,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'player_id',r.player_id,
          'name',r.display_name,
          'shirt_number',r.shirt_number
        ) order by r.display_name)
        from roster r
        join public.fixture_availability_responses ar
          on ar.fixture_id=po.fixture_id
         and ar.player_id=r.player_id
         and ar.available
      ),'[]'::jsonb) as available_players,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'player_id',r.player_id,
          'name',r.display_name,
          'shirt_number',r.shirt_number
        ) order by r.display_name)
        from roster r
        join public.fixture_availability_responses ar
          on ar.fixture_id=po.fixture_id
         and ar.player_id=r.player_id
         and not ar.available
      ),'[]'::jsonb) as unavailable_players,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'player_id',r.player_id,
          'name',r.display_name,
          'shirt_number',r.shirt_number
        ) order by r.display_name)
        from roster r
        where not exists (
          select 1 from public.fixture_availability_responses ar
          where ar.fixture_id=po.fixture_id and ar.player_id=r.player_id
        )
      ),'[]'::jsonb) as no_response_players,
      coalesce((
        select jsonb_agg(ms.player_id order by ms.player_id)
        from public.match_squads ms
        where ms.fixture_id=po.fixture_id and ms.selected
      ),'[]'::jsonb) as saved_squad
    from polls po
  ),
  stats as (
    select
      r.player_id,
      r.display_name as name,
      r.shirt_number,
      count(po.fixture_id) filter(
        where (po.kick_off is null or po.kick_off>=r.joined_at)
          and (po.kick_off<=now() or ar.fixture_id is not null)
      )::int as games_asked,
      count(ar.fixture_id) filter(
        where (po.kick_off is null or po.kick_off>=r.joined_at) and ar.available
      )::int as available,
      count(ar.fixture_id) filter(
        where (po.kick_off is null or po.kick_off>=r.joined_at) and not ar.available
      )::int as unavailable,
      count(po.fixture_id) filter(
        where (po.kick_off is null or po.kick_off>=r.joined_at)
          and po.kick_off<=now()
          and ar.fixture_id is null
      )::int as no_response,
      case
        when count(ar.fixture_id) filter(where po.kick_off is null or po.kick_off>=r.joined_at)>0
          then round(
            100.0 * count(ar.fixture_id) filter(
              where (po.kick_off is null or po.kick_off>=r.joined_at) and ar.available
            )
            /
            count(ar.fixture_id) filter(where po.kick_off is null or po.kick_off>=r.joined_at)
          )::int
        else null
      end as availability_pct,
      case
        when count(po.fixture_id) filter(
          where (po.kick_off is null or po.kick_off>=r.joined_at)
            and (po.kick_off<=now() or ar.fixture_id is not null)
        )>0
          then round(
            100.0 * count(ar.fixture_id) filter(where po.kick_off is null or po.kick_off>=r.joined_at)
            /
            count(po.fixture_id) filter(
              where (po.kick_off is null or po.kick_off>=r.joined_at)
                and (po.kick_off<=now() or ar.fixture_id is not null)
            )
          )::int
        else null
      end as response_rate_pct
    from roster r
    left join polls po on true
    left join public.fixture_availability_responses ar
      on ar.fixture_id=po.fixture_id and ar.player_id=r.player_id
    group by r.player_id,r.display_name,r.shirt_number
  )
  select jsonb_build_object(
    'fixtures',coalesce((
      select jsonb_agg(jsonb_build_object(
        'fixture_id',fr.fixture_id,
        'opponent',fr.opponent,
        'venue',fr.venue,
        'competition',fr.competition,
        'kick_off',fr.kick_off,
        'status',fr.status,
        'ground_name',fr.ground_name,
        'ground_address',fr.ground_address,
        'ground_postcode',fr.ground_postcode,
        'gameweek_number',fr.gameweek_number,
        'available',fr.available_players,
        'unavailable',fr.unavailable_players,
        'no_response',fr.no_response_players,
        'available_count',jsonb_array_length(fr.available_players),
        'unavailable_count',jsonb_array_length(fr.unavailable_players),
        'no_response_count',jsonb_array_length(fr.no_response_players),
        'saved_squad',fr.saved_squad
      ) order by fr.kick_off
      ) from fixture_rows fr
    ),'[]'::jsonb),
    'player_stats',coalesce((
      select jsonb_agg(to_jsonb(s) order by s.name) from stats s
    ),'[]'::jsonb)
  ) into v_result;

  return coalesce(v_result,jsonb_build_object('fixtures','[]'::jsonb,'player_stats','[]'::jsonb));
end;
$function$;
