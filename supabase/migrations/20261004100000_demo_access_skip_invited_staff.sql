-- New accounts get read access to the Harbour Athletic demo club, except people
-- invited to a real team (email invite or share link). They only see their own team.
create or replace function public.grant_core_demo_access()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  demo_club_id uuid;
  demo_team_id uuid;
begin
  -- Skip invited staff.
  if exists (
    select 1 from auth.users u
    where u.id = new.id
      and lower(coalesce(u.raw_user_meta_data->>'footballpa_staff_invite','false')) = 'true'
  ) or exists (
    select 1 from public.pending_team_access p
    join auth.users u on lower(u.email) = lower(p.email)
    where u.id = new.id
  ) then
    return new;
  end if;

  select id into demo_club_id from public.clubs where slug = 'harbour-athletic' limit 1;
  if demo_club_id is null then
    return new;
  end if;

  insert into public.club_memberships (club_id, user_id, role, permissions, active)
  values (demo_club_id, new.id, 'member', array['match','dashboard'], true)
  on conflict (club_id, user_id) do nothing;

  select id into demo_team_id from public.teams where club_id = demo_club_id and slug = 'first-team' limit 1;
  if demo_team_id is not null then
    insert into public.team_memberships (team_id, user_id, role, permissions, active)
    values (demo_team_id, new.id, 'member', array['match','dashboard'], true)
    on conflict (team_id, user_id) do nothing;
  end if;

  return new;
end;
$function$;
