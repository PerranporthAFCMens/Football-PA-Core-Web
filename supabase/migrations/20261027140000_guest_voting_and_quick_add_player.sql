-- Guest voting link and quick "add a player" for a match.
--
-- Everything here is NEW. No existing function, table or the Player Portal is changed.
--
-- Guest voting
--   * Each voting event gets its own unique link token (voting_events.public_token already exists).
--   * Guests give a name and vote with the same rules as portal players:
--       3 / 2 / 1 points, optional Dick of the Day with a reason.
--   * The names a guest may vote for follow the player rule exactly:
--       the game's selected squad if one is saved, otherwise the active team players.
--   * One ballot per name. Voting again with the same name changes that guest's vote.
--   * Guest ballots sit in the same voting_ballots / voting_selections tables, so the
--     existing results (Top 3, Dick of the Day) count them with no change.
--
-- Quick add player
--   * Adds (or re-activates) a player for a team. If the game already has a saved squad
--     the player is also selected into it; otherwise only the team list changes.

-- 1. Manager: create or fetch the guest link token for a voting event
create or replace function public.voting_guest_link(p_event_id uuid, p_regenerate boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_team uuid;
  v_token uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  select ve.team_id, ve.public_token into v_team, v_token
  from public.voting_events ve where ve.id = p_event_id;
  if v_team is null then raise exception 'Voting event not found'; end if;

  if not public.can_manage_voting(v_team) then
    raise exception 'You do not have Voting Centre permission';
  end if;

  if v_token is null or coalesce(p_regenerate, false) then
    v_token := gen_random_uuid();
    update public.voting_events set public_token = v_token, updated_at = now() where id = p_event_id;
  end if;

  return jsonb_build_object('token', v_token);
end;
$function$;

-- 2. Manager: list guest voters for an event
create or replace function public.voting_guest_voters(p_event_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_team uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  select ve.team_id into v_team from public.voting_events ve where ve.id = p_event_id;
  if v_team is null then raise exception 'Voting event not found'; end if;

  if not public.can_manage_voting(v_team) then
    raise exception 'You do not have Voting Centre permission';
  end if;

  return coalesce((
    select jsonb_agg(b.metadata->>'guest_name' order by b.submitted_at)
    from public.voting_ballots b
    where b.event_id = p_event_id and b.voter_key like 'guest:%'
  ), '[]'::jsonb);
end;
$function$;

-- 3. Guest (no login): what the guest voting page needs
create or replace function public.guest_vote_data(p_token uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  ve public.voting_events%rowtype;
  v_team public.teams%rowtype;
  v_club public.clubs%rowtype;
  v_has_squad boolean := false;
  v_candidates jsonb;
begin
  if p_token is null then return jsonb_build_object('status', 'invalid'); end if;

  select * into ve from public.voting_events where public_token = p_token;
  if not found then return jsonb_build_object('status', 'invalid'); end if;

  select * into v_team from public.teams where id = ve.team_id;
  select * into v_club from public.clubs where id = ve.club_id;

  if ve.status <> 'open'
     or (ve.opens_at is not null and ve.opens_at > now())
     or (ve.closes_at is not null and ve.closes_at <= now()) then
    return jsonb_build_object('status', 'closed', 'title', ve.title,
      'team', jsonb_build_object('name', v_team.name, 'badge_url', v_team.badge_url),
      'club', jsonb_build_object('name', v_club.name, 'primary_colour', v_club.primary_colour));
  end if;

  if ve.fixture_id is not null then
    select exists(select 1 from public.match_squads ms where ms.fixture_id = ve.fixture_id and ms.selected)
    into v_has_squad;
  end if;

  if v_has_squad then
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name) order by x.name), '[]'::jsonb)
    into v_candidates
    from (
      select distinct p.id, p.display_name as name
      from public.match_squads ms
      join public.players p on p.id = ms.player_id
      where ms.fixture_id = ve.fixture_id and ms.selected and p.active
    ) x;
  else
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name) order by x.name), '[]'::jsonb)
    into v_candidates
    from (
      select distinct p.id, p.display_name as name
      from public.team_players tp
      join public.players p on p.id = tp.player_id
      where tp.team_id = ve.team_id and tp.active and p.active
    ) x;
  end if;

  return jsonb_build_object(
    'status', 'open',
    'title', ve.title,
    'team', jsonb_build_object('name', v_team.name, 'badge_url', v_team.badge_url),
    'club', jsonb_build_object('name', v_club.name, 'primary_colour', v_club.primary_colour),
    'candidates', v_candidates
  );
end;
$function$;

-- 4. Guest (no login): submit a ballot
create or replace function public.guest_vote_submit(
  p_token uuid, p_guest_name text,
  p_rank1 uuid, p_rank2 uuid, p_rank3 uuid, p_fun uuid,
  p_reason text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  ve public.voting_events%rowtype;
  v_name text := regexp_replace(btrim(coalesce(p_guest_name, '')), '\s+', ' ', 'g');
  v_key text;
  v_has_squad boolean := false;
  v_rank_q uuid;
  v_fun_q uuid;
  v_ballot uuid;
begin
  if p_token is null then raise exception 'This voting link is not valid'; end if;
  if length(v_name) < 2 or length(v_name) > 60 then raise exception 'Enter your name'; end if;

  select * into ve from public.voting_events where public_token = p_token;
  if not found then raise exception 'This voting link is not valid'; end if;

  if ve.status <> 'open'
     or (ve.opens_at is not null and ve.opens_at > now())
     or (ve.closes_at is not null and ve.closes_at <= now()) then
    raise exception 'Voting is not open';
  end if;

  if p_rank1 is null or p_rank2 is null or p_rank3 is null
     or p_rank1 = p_rank2 or p_rank1 = p_rank3 or p_rank2 = p_rank3 then
    raise exception 'Choose three different players';
  end if;

  if ve.fixture_id is not null then
    select exists(select 1 from public.match_squads ms where ms.fixture_id = ve.fixture_id and ms.selected)
    into v_has_squad;
  end if;

  if exists (
    select 1
    from (values (p_rank1), (p_rank2), (p_rank3), (p_fun)) x(id)
    where id is not null
      and not (
        case
          when v_has_squad then exists (
            select 1 from public.match_squads ms
            join public.players p on p.id = ms.player_id
            where ms.fixture_id = ve.fixture_id and ms.player_id = x.id and ms.selected and p.active)
          else exists (
            select 1 from public.team_players tp
            join public.players p on p.id = tp.player_id
            where tp.team_id = ve.team_id and tp.player_id = x.id and tp.active and p.active)
        end
      )
  ) then
    raise exception 'Invalid player selection';
  end if;

  select id into v_rank_q from public.voting_questions
  where template_id = ve.template_id and question_type = 'ranked' order by sort_order limit 1;

  select id into v_fun_q from public.voting_questions
  where template_id = ve.template_id and question_type = 'single' order by sort_order limit 1;

  v_key := 'guest:' || lower(v_name);

  select id into v_ballot from public.voting_ballots
  where event_id = ve.id and voter_key = v_key limit 1;

  if v_ballot is null then
    insert into public.voting_ballots(event_id, voter_key, metadata)
    values (ve.id, v_key, jsonb_build_object('source', 'guest_link', 'guest_name', v_name))
    returning id into v_ballot;
  else
    delete from public.voting_selections where ballot_id = v_ballot;
    update public.voting_ballots
    set submitted_at = now(),
        metadata = jsonb_build_object('source', 'guest_link', 'guest_name', v_name)
    where id = v_ballot;
  end if;

  insert into public.voting_selections(ballot_id, question_id, player_id, rank, points)
  values (v_ballot, v_rank_q, p_rank1, 1, 3),
         (v_ballot, v_rank_q, p_rank2, 2, 2),
         (v_ballot, v_rank_q, p_rank3, 3, 1);

  if v_fun_q is not null and p_fun is not null then
    insert into public.voting_selections(ballot_id, question_id, player_id, rank, points, reason)
    values (v_ballot, v_fun_q, p_fun, 1, 1, nullif(btrim(p_reason), ''));
  end if;

  return jsonb_build_object('ok', true);
end;
$function$;

-- 5. Manager: add a player on the fly, optionally selecting them for a game
create or replace function public.add_player_quick(
  p_team_id uuid, p_first_name text, p_last_name text,
  p_season_id uuid default null, p_fixture_id uuid default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_club uuid;
  v_first text := btrim(coalesce(p_first_name, ''));
  v_last text := btrim(coalesce(p_last_name, ''));
  v_name text;
  v_player uuid;
  v_season uuid := p_season_id;
  v_tp uuid;
  v_in_squad boolean := false;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_manage_players(p_team_id) then
    raise exception 'You do not have permission to manage players';
  end if;
  if v_first = '' then raise exception 'Enter a first name'; end if;

  select t.club_id into v_club from public.teams t where t.id = p_team_id;
  if v_club is null then raise exception 'Team not found'; end if;

  if v_season is null and p_fixture_id is not null then
    select f.season_id into v_season from public.fixtures f
    where f.id = p_fixture_id and f.team_id = p_team_id;
  end if;

  v_name := btrim(v_first || ' ' || v_last);

  select p.id into v_player from public.players p
  where p.club_id = v_club
    and lower(coalesce(p.first_name, '')) = lower(v_first)
    and lower(coalesce(p.last_name, '')) = lower(v_last)
  order by p.active desc, p.created_at
  limit 1;

  if v_player is null then
    insert into public.players(club_id, first_name, last_name, display_name, active)
    values (v_club, v_first, nullif(v_last, ''), v_name, true)
    returning id into v_player;
  else
    update public.players set active = true, updated_at = now() where id = v_player;
  end if;

  select tp.id into v_tp from public.team_players tp
  where tp.team_id = p_team_id and tp.player_id = v_player
    and tp.season_id is not distinct from v_season
  limit 1;

  if v_tp is null then
    insert into public.team_players(team_id, player_id, season_id, active)
    values (p_team_id, v_player, v_season, true);
  else
    update public.team_players set active = true, updated_at = now() where id = v_tp;
  end if;

  if p_fixture_id is not null then
    if not exists (select 1 from public.fixtures f where f.id = p_fixture_id and f.team_id = p_team_id) then
      raise exception 'Fixture not found for this team';
    end if;
    -- Only join a squad that already exists. If no squad has been saved for the game yet,
    -- creating a one-player squad would shrink the voting list to just that player.
    if exists (select 1 from public.match_squads ms where ms.fixture_id = p_fixture_id and ms.selected) then
      if exists (select 1 from public.match_squads ms where ms.fixture_id = p_fixture_id and ms.player_id = v_player) then
        update public.match_squads set selected = true, updated_at = now()
        where fixture_id = p_fixture_id and player_id = v_player;
      else
        insert into public.match_squads(fixture_id, player_id, selected)
        values (p_fixture_id, v_player, true);
      end if;
      v_in_squad := true;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'player_id', v_player, 'name', v_name, 'in_squad', v_in_squad);
end;
$function$;

-- Access: guests can only use the two guest functions. The rest need a signed-in manager.
revoke all on function public.voting_guest_link(uuid, boolean) from public, anon;
revoke all on function public.voting_guest_voters(uuid) from public, anon;
revoke all on function public.add_player_quick(uuid, text, text, uuid, uuid) from public, anon;
revoke all on function public.guest_vote_data(uuid) from public;
revoke all on function public.guest_vote_submit(uuid, text, uuid, uuid, uuid, uuid, text) from public;

grant execute on function public.voting_guest_link(uuid, boolean) to authenticated;
grant execute on function public.voting_guest_voters(uuid) to authenticated;
grant execute on function public.add_player_quick(uuid, text, text, uuid, uuid) to authenticated;
grant execute on function public.guest_vote_data(uuid) to anon, authenticated;
grant execute on function public.guest_vote_submit(uuid, text, uuid, uuid, uuid, uuid, text) to anon, authenticated;
