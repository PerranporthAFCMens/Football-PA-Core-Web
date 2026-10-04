-- Shareable staff invite links (send by text or WhatsApp instead of email).
-- A manager creates a link for one access level. The link works once and
-- expires after 7 days. Only a hash of the link's secret is stored.

create table if not exists public.team_invite_links (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  access_level_id uuid not null references public.team_access_levels(id) on delete cascade,
  role text not null check (role in ('team_admin','manager','coach','treasurer')),
  token_hash text not null unique,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  used_by uuid
);

-- No policies: the table is only reachable through the functions below.
alter table public.team_invite_links enable row level security;

-- 1. Create a link (managers with Access Management permission only).
create or replace function public.create_team_invite_link(p_team_id uuid, p_access_level_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_level public.team_access_levels%rowtype;
  v_role text;
  v_token text;
  v_expires timestamptz := now() + interval '7 days';
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_manage_access(p_team_id) then raise exception 'You do not have permission to manage access'; end if;

  select * into v_level from public.team_access_levels
  where id = p_access_level_id and team_id = p_team_id and active;
  if not found then raise exception 'Access level not found'; end if;

  -- Same mapping the Access Management page already uses.
  v_role := case when v_level.name = 'Manager' then 'manager' else 'coach' end;

  v_token := translate(encode(gen_random_bytes(18), 'base64'), '+/=', '-_');

  insert into public.team_invite_links(team_id, access_level_id, role, token_hash, created_by, expires_at)
  values (p_team_id, p_access_level_id, v_role, encode(digest(v_token, 'sha256'), 'hex'), auth.uid(), v_expires);

  return jsonb_build_object('token', v_token, 'expires_at', v_expires, 'level_name', v_level.name);
end;
$$;

-- 2. Look at a link without using it (shown on the join page before sign-up).
create or replace function public.peek_team_invite_link(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_link public.team_invite_links%rowtype;
  v_team public.teams%rowtype;
  v_club public.clubs%rowtype;
  v_level_name text;
begin
  select * into v_link from public.team_invite_links
  where token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex');
  if not found then return jsonb_build_object('valid', false, 'reason', 'This invite link is not valid.'); end if;
  if v_link.used_at is not null then return jsonb_build_object('valid', false, 'reason', 'This invite link has already been used. Ask for a new one.'); end if;
  if v_link.expires_at < now() then return jsonb_build_object('valid', false, 'reason', 'This invite link has expired. Ask for a new one.'); end if;

  select * into v_team from public.teams where id = v_link.team_id;
  select * into v_club from public.clubs where id = v_team.club_id;
  select name into v_level_name from public.team_access_levels where id = v_link.access_level_id;

  return jsonb_build_object(
    'valid', true,
    'team_id', v_team.id,
    'team_name', v_team.name,
    'club_name', v_club.name,
    'level_name', case when v_level_name = 'Manager' then 'Team Owner' else v_level_name end,
    'badge_url', coalesce(v_team.badge_url, v_club.badge_url),
    'primary_colour', v_club.primary_colour
  );
end;
$$;

-- 3. Use a link for a given user. Internal: only the server (service role) can call this directly.
create or replace function public.claim_team_invite_link_for_user(p_token text, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_link public.team_invite_links%rowtype;
  v_permissions text[];
begin
  if p_user_id is null then raise exception 'Authentication required'; end if;

  select * into v_link from public.team_invite_links
  where token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex')
  for update;
  if not found then raise exception 'This invite link is not valid.'; end if;
  if v_link.used_at is not null then raise exception 'This invite link has already been used. Ask for a new one.'; end if;
  if v_link.expires_at < now() then raise exception 'This invite link has expired. Ask for a new one.'; end if;

  select permissions into v_permissions from public.team_access_levels
  where id = v_link.access_level_id and team_id = v_link.team_id and active;
  if not found then raise exception 'The access level for this invite no longer exists.'; end if;

  insert into public.team_memberships(team_id, user_id, role, permissions, active, access_level_id)
  values (v_link.team_id, p_user_id, v_link.role, coalesce(v_permissions, '{}'::text[]), true, v_link.access_level_id)
  on conflict (team_id, user_id) do update
    set role = excluded.role,
        permissions = excluded.permissions,
        access_level_id = excluded.access_level_id,
        active = true,
        updated_at = now();

  update public.team_invite_links set used_at = now(), used_by = p_user_id where id = v_link.id;

  return jsonb_build_object('team_id', v_link.team_id);
end;
$$;

-- 4. Use a link as the signed-in user (people who already have a Football PA account).
create or replace function public.claim_team_invite_link(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  return public.claim_team_invite_link_for_user(p_token, auth.uid());
end;
$$;

revoke all on function public.create_team_invite_link(uuid, uuid) from public, anon;
revoke all on function public.peek_team_invite_link(text) from public;
revoke all on function public.claim_team_invite_link_for_user(text, uuid) from public, anon, authenticated;
revoke all on function public.claim_team_invite_link(text) from public, anon;

grant execute on function public.create_team_invite_link(uuid, uuid) to authenticated;
grant execute on function public.peek_team_invite_link(text) to anon, authenticated, service_role;
grant execute on function public.claim_team_invite_link_for_user(text, uuid) to service_role;
grant execute on function public.claim_team_invite_link(text) to authenticated;
