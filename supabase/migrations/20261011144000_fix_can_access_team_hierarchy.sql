-- Fix access control hierarchy: can_access_team() function
--
-- ISSUE: Regular club members could access all teams in their club.
-- This violated team isolation and the intended access hierarchy:
--   - Club Owner: can access all teams in their club
--   - Team Member/Coach/Player: can access only their explicit teams
--
-- FIX: Modified can_access_team() to require club_memberships.role = 'owner'
--      before granting club-wide team access. Regular club members now only
--      access teams they're explicitly a member of via team_memberships.
--
-- IMPACT:
--   - Perranporth AFC club owner: maintains access to all Perranporth teams
--   - St Agnes club owner: maintains access to all St Agnes teams
--   - Coach/Player/Staff at Perranporth: loses automatic access to all Perranporth teams
--                                         must be explicitly added to each team via team_memberships
--   - Prevents data leakage: teams can no longer be discovered via club membership alone
--
-- TESTED:
--   - is_platform_admin() still grants access (line 1 of condition)
--   - Explicit team_memberships still grant access (line 2)
--   - Club owners still grant access to all club teams (line 3, with role='owner')
--   - Club members no longer grant access (line 3 now filters by role='owner')

CREATE OR REPLACE FUNCTION public.can_access_team(p_team_id uuid)
RETURNS boolean AS $$
  select auth.uid() is not null and (
    public.is_platform_admin()
    or exists (
      select 1
      from public.team_memberships tm
      where tm.team_id = p_team_id
        and tm.user_id = auth.uid()
        and tm.active
    )
    or exists (
      select 1
      from public.teams t
      join public.club_memberships cm on cm.club_id = t.club_id
      where t.id = p_team_id
        and cm.user_id = auth.uid()
        and cm.active
        and cm.role = 'owner'
    )
  );
$$ LANGUAGE sql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.can_access_team TO authenticated, anon;
