-- 1. Remember the name typed in when someone is invited by email,
--    so Pending invitations show a name, not just an email address.
alter table public.pending_team_access add column if not exists display_name text;

-- 2. Retire "Legacy access": give every staff membership (and pending invite)
--    without an Access Level the matching level for its role.
--    Permissions do not change: each level has the same permissions the old role had.
--      team_admin -> Team Admin, manager -> Manager (shown as Team Owner),
--      coach -> Coach, treasurer -> Treasurer
update public.team_memberships tm
set access_level_id = l.id, updated_at = now()
from public.team_access_levels l
where tm.access_level_id is null
  and tm.role in ('team_admin','manager','coach','treasurer')
  and l.team_id = tm.team_id
  and l.active
  and l.name = case tm.role
                 when 'team_admin' then 'Team Admin'
                 when 'manager' then 'Manager'
                 when 'coach' then 'Coach'
                 when 'treasurer' then 'Treasurer'
               end;

update public.pending_team_access p
set access_level_id = l.id, updated_at = now()
from public.team_access_levels l
where p.access_level_id is null
  and p.role in ('team_admin','manager','coach','treasurer')
  and l.team_id = p.team_id
  and l.active
  and l.name = case p.role
                 when 'team_admin' then 'Team Admin'
                 when 'manager' then 'Manager'
                 when 'coach' then 'Coach'
                 when 'treasurer' then 'Treasurer'
               end;

-- 3. Include the invited person's name in the Access Management listing.
create or replace function public.list_team_access_management(p_team_id uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'auth'
as $function$
declare
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_manage_access(p_team_id) then raise exception 'You do not have permission to manage access'; end if;

  select jsonb_build_object(
    'team',jsonb_build_object('id',t.id,'name',t.name,'club_id',t.club_id),
    'levels',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',l.id,'name',l.name,'description',l.description,
        'permissions',l.permissions,'active',l.active
      ) order by l.name)
      from public.team_access_levels l
      where l.team_id=p_team_id and l.active
    ),'[]'::jsonb),
    'staff',coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id',tm.user_id,
        'role',tm.role,
        'permissions',tm.permissions,
        'active',tm.active,
        'access_level_id',tm.access_level_id,
        'access_level_name',l.name,
        'name',coalesce(pr.display_name,split_part(coalesce(pr.email,u.email,''),'@',1),'User'),
        'email',coalesce(pr.email,u.email),
        'email_confirmed',u.email_confirmed_at is not null,
        'last_sign_in_at',u.last_sign_in_at
      ) order by coalesce(pr.display_name,pr.email,u.email))
      from public.team_memberships tm
      left join public.profiles pr on pr.id=tm.user_id
      left join auth.users u on u.id=tm.user_id
      left join public.team_access_levels l on l.id=tm.access_level_id
      where tm.team_id=p_team_id
        and (tm.role in ('team_admin','manager','coach','treasurer') or tm.access_level_id is not null)
    ),'[]'::jsonb),
    'pending',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'email',p.email,'name',p.display_name,'role',p.role,'permissions',p.permissions,
        'access_level_id',p.access_level_id,'access_level_name',l.name,
        'created_at',p.created_at
      ) order by p.created_at desc)
      from public.pending_team_access p
      left join public.team_access_levels l on l.id=p.access_level_id
      where p.team_id=p_team_id and p.active and p.claimed_at is null
    ),'[]'::jsonb),
    'players',coalesce((
      select jsonb_agg(jsonb_build_object(
        'player_id',x.player_id,
        'name',x.display_name,
        'shirt_number',x.shirt_number,
        'roster_active',x.roster_active,
        'portal_status',case
          when c.player_id is null then 'not_set_up'
          when c.active then 'active'
          else 'removed'
        end,
        'active_sessions',coalesce(s.session_count,0)
      ) order by x.display_name)
      from (
        select p.id as player_id,p.display_name,p.shirt_number,bool_or(tp.active) as roster_active
        from public.team_players tp
        join public.players p on p.id=tp.player_id
        where tp.team_id=p_team_id
        group by p.id,p.display_name,p.shirt_number
      ) x
      left join public.player_portal_credentials c
        on c.team_id=p_team_id and c.player_id=x.player_id
      left join lateral (
        select count(*)::int session_count
        from public.player_portal_sessions ps
        where ps.team_id=p_team_id and ps.player_id=x.player_id and ps.expires_at>now()
      ) s on true
    ),'[]'::jsonb)
  ) into v_result
  from public.teams t
  where t.id=p_team_id;

  if v_result is null then raise exception 'Team not found'; end if;
  return v_result;
end;
$function$;
