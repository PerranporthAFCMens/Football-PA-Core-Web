-- Restores public.get_team_availability to its original definition.
--
-- An earlier version of this migration replaced the function with a hand-written query.
-- That broke the Availability page (wrong ordering, missing gameweek_number / status /
-- saved_squad / player_stats, and every fixture listed instead of only polled ones).
--
-- The real logic lives in private.build_team_availability, which already returns
-- ground_name, ground_address and ground_postcode. This wrapper only adds the auth
-- checks and the can_manage flag. If "Venue TBC" shows, the fixture row has no ground
-- stored by the fixture sync; it is not an RPC problem.

CREATE OR REPLACE FUNCTION public.get_team_availability(p_team_id uuid, p_season_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_access_team(p_team_id) then
    raise exception 'You do not have access to this team';
  end if;

  v_result:=private.build_team_availability(p_team_id,p_season_id);

  return v_result || jsonb_build_object(
    'can_manage',public.team_has_capability(p_team_id,'match')
  );
end;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_team_availability(uuid, uuid) FROM anon, public;
