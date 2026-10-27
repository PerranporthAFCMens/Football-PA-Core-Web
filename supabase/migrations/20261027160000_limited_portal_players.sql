-- Limited portal players: a player can be set to "limited" so the Player Portal only shows
-- games they are invited to (in the saved squad, or invited by the manager).
create table if not exists public.portal_player_limits (
  team_id uuid not null references public.teams(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  limited boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (team_id, player_id)
);
create table if not exists public.portal_fixture_invites (
  team_id uuid not null references public.teams(id) on delete cascade,
  fixture_id uuid not null references public.fixtures(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (fixture_id, player_id)
);
alter table public.portal_player_limits enable row level security;
alter table public.portal_fixture_invites enable row level security;
revoke all on public.portal_player_limits, public.portal_fixture_invites from public, anon, authenticated;

create or replace function public.get_portal_limits(p_team_id uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_manage_players(p_team_id) then raise exception 'You do not have permission to manage players'; end if;
  return jsonb_build_object(
    'limited', coalesce((select jsonb_agg(player_id) from public.portal_player_limits where team_id = p_team_id and limited), '[]'::jsonb),
    'invites', coalesce((select jsonb_agg(jsonb_build_object('fixture_id', fixture_id, 'player_id', player_id)) from public.portal_fixture_invites where team_id = p_team_id), '[]'::jsonb));
end;
$function$;

create or replace function public.set_player_portal_limited(p_team_id uuid, p_player_id uuid, p_limited boolean)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_manage_players(p_team_id) then raise exception 'You do not have permission to manage players'; end if;
  insert into public.portal_player_limits(team_id, player_id, limited, updated_at)
  values (p_team_id, p_player_id, coalesce(p_limited, false), now())
  on conflict (team_id, player_id) do update set limited = excluded.limited, updated_at = now();
  return jsonb_build_object('ok', true, 'limited', coalesce(p_limited, false));
end;
$function$;

create or replace function public.set_portal_fixture_invite(p_team_id uuid, p_fixture_id uuid, p_player_id uuid, p_invited boolean)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_manage_players(p_team_id) then raise exception 'You do not have permission to manage players'; end if;
  if not exists (select 1 from public.fixtures f where f.id = p_fixture_id and f.team_id = p_team_id) then
    raise exception 'Fixture not found for this team';
  end if;
  if coalesce(p_invited, false) then
    insert into public.portal_fixture_invites(team_id, fixture_id, player_id) values (p_team_id, p_fixture_id, p_player_id)
    on conflict (fixture_id, player_id) do nothing;
  else
    delete from public.portal_fixture_invites where fixture_id = p_fixture_id and player_id = p_player_id;
  end if;
  return jsonb_build_object('ok', true);
end;
$function$;

-- Portal availability list (PIN login): same as before, but limited players only see invited games.
create or replace function public.player_portal_availability(p_token text)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'extensions'
as $function$
declare
  v_team uuid;
  v_player uuid;
  v_season uuid;
  v_result jsonb;
begin
  select s.team_id,s.player_id,tseason.id
    into v_team,v_player,v_season
  from public.player_portal_sessions s
  join public.teams t on t.id=s.team_id
  left join public.seasons tseason on tseason.club_id=t.club_id and tseason.label=t.season_label
  where s.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
    and s.expires_at>now();

  if v_team is null or v_player is null then
    raise exception 'Player session expired';
  end if;

  v_result:=private.build_team_availability(v_team,v_season);

  if exists (select 1 from public.portal_player_limits l where l.team_id=v_team and l.player_id=v_player and l.limited) then
    v_result:=jsonb_set(v_result,'{fixtures}',coalesce((
      select jsonb_agg(f order by f->>'kick_off')
      from jsonb_array_elements(v_result->'fixtures') f
      where (f->'saved_squad') ? v_player::text
         or exists (select 1 from public.portal_fixture_invites i
                    where i.player_id=v_player and i.fixture_id=(f->>'fixture_id')::uuid)
    ),'[]'::jsonb));
    v_result:=jsonb_set(v_result,'{player_stats}',coalesce((
      select jsonb_agg(s)
      from jsonb_array_elements(v_result->'player_stats') s
      where (s->>'player_id')::uuid=v_player
    ),'[]'::jsonb));
  end if;

  return v_result || jsonb_build_object('viewer_player_id',v_player);
end;
$function$;

-- Portal home (signed-in account): keep the original as get_my_player_portal_base and filter recent games.
do $$
begin
  if to_regprocedure('public.get_my_player_portal_base()') is null then
    alter function public.get_my_player_portal() rename to get_my_player_portal_base;
    revoke all on function public.get_my_player_portal_base() from public, anon, authenticated;
  end if;
end $$;

create or replace function public.get_my_player_portal()
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_res jsonb := public.get_my_player_portal_base();
  v_team uuid := nullif(v_res #>> '{team,id}','')::uuid;
  v_player uuid := nullif(v_res #>> '{player,id}','')::uuid;
begin
  if v_res is not null and exists (select 1 from public.portal_player_limits l where l.team_id=v_team and l.player_id=v_player and l.limited) then
    v_res := jsonb_set(v_res,'{recent_fixtures}',coalesce((
      select jsonb_agg(f order by f->>'kick_off' desc)
      from jsonb_array_elements(v_res->'recent_fixtures') f
      where exists (select 1 from public.match_squads ms where ms.fixture_id=(f->>'id')::uuid and ms.player_id=v_player and ms.selected)
         or exists (select 1 from public.portal_fixture_invites i where i.fixture_id=(f->>'id')::uuid and i.player_id=v_player)
    ),'[]'::jsonb));
  end if;
  return v_res;
end;
$function$;

revoke all on function public.get_portal_limits(uuid), public.set_player_portal_limited(uuid, uuid, boolean),
  public.set_portal_fixture_invite(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function public.get_portal_limits(uuid), public.set_player_portal_limited(uuid, uuid, boolean),
  public.set_portal_fixture_invite(uuid, uuid, uuid, boolean) to authenticated;
revoke all on function public.get_my_player_portal() from public, anon;
grant execute on function public.get_my_player_portal() to authenticated;
grant execute on function public.player_portal_availability(text) to anon, authenticated;
