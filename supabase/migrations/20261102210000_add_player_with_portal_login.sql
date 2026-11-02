-- Add a player properly: player record, squad place, and a Player Portal login record
-- (date of birth + temporary PIN) so they can use "First time here?" without any SQL.

create or replace function public.add_team_player(
  p_team_id uuid, p_first_name text, p_last_name text, p_date_of_birth date,
  p_reserve boolean default false, p_season_id uuid default null)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare
  v_club uuid; v_first text := btrim(coalesce(p_first_name, '')); v_last text := btrim(coalesce(p_last_name, ''));
  v_name text; v_player uuid; v_tp uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_manage_players(p_team_id) then raise exception 'You do not have permission to manage players'; end if;
  if v_first = '' or v_last = '' then raise exception 'Enter a first name and surname'; end if;
  if p_date_of_birth is null then raise exception 'Enter a date of birth (the player uses it to sign up)'; end if;
  select t.club_id into v_club from public.teams t where t.id = p_team_id;
  if v_club is null then raise exception 'Team not found'; end if;
  v_name := btrim(v_first || ' ' || v_last);

  select p.id into v_player from public.players p
  where p.club_id = v_club and lower(coalesce(p.first_name, '')) = lower(v_first)
    and lower(coalesce(p.last_name, '')) = lower(v_last)
  order by p.active desc, p.created_at limit 1;
  if v_player is null then
    insert into public.players(club_id, first_name, last_name, display_name, active)
    values (v_club, v_first, v_last, v_name, true) returning id into v_player;
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

  perform public.give_player_portal_access(p_team_id, v_player, p_date_of_birth);

  if p_reserve then
    insert into public.team_guest_players(team_id, player_id) values (p_team_id, v_player) on conflict do nothing;
    insert into public.portal_player_limits(team_id, player_id, limited, updated_at) values (p_team_id, v_player, true, now())
    on conflict (team_id, player_id) do update set limited = true, updated_at = now();
  end if;
  return jsonb_build_object('ok', true, 'player_id', v_player, 'name', v_name);
end;
$function$;

-- Give an existing player a portal login record (or reset it). They then sign up with
-- "First time here?" using their name, date of birth and a PIN they choose.
create or replace function public.give_player_portal_access(p_team_id uuid, p_player_id uuid, p_date_of_birth date)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_manage_players(p_team_id) then raise exception 'You do not have permission to manage players'; end if;
  if p_date_of_birth is null then raise exception 'Enter a date of birth'; end if;
  if not exists (select 1 from public.team_players where team_id = p_team_id and player_id = p_player_id) then
    raise exception 'That player is not in this team';
  end if;
  insert into public.player_portal_credentials(team_id, player_id, pin_hash, pin_chosen, date_of_birth, active, failed_attempts, locked_until)
  values (p_team_id, p_player_id,
          extensions.crypt(replace(gen_random_uuid()::text, '-', ''), extensions.gen_salt('bf', 8)),
          false, p_date_of_birth, true, 0, null)
  on conflict (team_id, player_id) do update
    set date_of_birth = excluded.date_of_birth, pin_hash = excluded.pin_hash, pin_chosen = false,
        active = true, failed_attempts = 0, locked_until = null, updated_at = now();
  return jsonb_build_object('ok', true);
end;
$function$;

-- Which players on this team have an active portal login record, and have they set a PIN yet.
create or replace function public.list_portal_logins(p_team_id uuid)
 returns table(player_id uuid, pin_chosen boolean)
 language plpgsql stable security definer set search_path to 'public'
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_manage_players(p_team_id) then raise exception 'You do not have permission to manage players'; end if;
  return query select c.player_id, c.pin_chosen from public.player_portal_credentials c
  where c.team_id = p_team_id and c.active;
end;
$function$;

revoke all on function public.add_team_player(uuid, text, text, date, boolean, uuid),
  public.give_player_portal_access(uuid, uuid, date), public.list_portal_logins(uuid) from public, anon;
grant execute on function public.add_team_player(uuid, text, text, date, boolean, uuid),
  public.give_player_portal_access(uuid, uuid, date), public.list_portal_logins(uuid) to authenticated;
