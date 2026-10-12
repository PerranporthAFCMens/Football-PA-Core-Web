-- Fix availability feature: include venue details in get_team_availability RPC
--
-- ISSUE: The get_team_availability RPC was not returning ground_name, ground_address,
--        and ground_postcode from the fixtures table, causing the availability.html UI
--        to show "Venue TBC" even when Full-Time data was synced with complete venue info.
--
-- FIX: Updated RPC SELECT to include all three ground fields in returned fixture objects.
--      The RPC builds a JSON response where each fixture includes ground_name, ground_address,
--      and ground_postcode fields alongside existing availability data.
--
-- IMPACT: Availability poll will now display venue name and address when synced from
--         Full-Time, and fall back to "Venue TBC" only when these fields are actually
--         empty in the database.

CREATE OR REPLACE FUNCTION public.get_team_availability(p_team_id uuid, p_season_id uuid DEFAULT NULL)
RETURNS jsonb AS $$
DECLARE
  v_can_manage boolean;
  v_fixtures jsonb;
BEGIN
  v_can_manage := public.can_manage_team(p_team_id);

  WITH fixture_data AS (
    SELECT
      f.id,
      f.opponent,
      f.competition,
      f.venue,
      f.ground_name,
      f.ground_address,
      f.ground_postcode,
      f.kick_off,
      jsonb_agg(jsonb_build_object('player_id', p.id, 'name', p.display_name, 'shirt_number', p.shirt_number) ORDER BY p.display_name)
        FILTER (WHERE r.available = true) as available,
      jsonb_agg(jsonb_build_object('player_id', p.id, 'name', p.display_name, 'shirt_number', p.shirt_number) ORDER BY p.display_name)
        FILTER (WHERE r.available = false) as unavailable,
      jsonb_agg(jsonb_build_object('player_id', p.id, 'name', p.display_name, 'shirt_number', p.shirt_number) ORDER BY p.display_name)
        FILTER (WHERE r.available IS NULL) as no_response,
      COUNT(*) FILTER (WHERE r.available = true) as available_count,
      COUNT(*) FILTER (WHERE r.available = false) as unavailable_count,
      COUNT(*) FILTER (WHERE r.available IS NULL) as no_response_count
    FROM public.fixtures f
    LEFT JOIN public.fixture_availability_responses r ON r.fixture_id = f.id
    LEFT JOIN public.players p ON p.id = r.player_id
    WHERE f.team_id = p_team_id
      AND (p_season_id IS NULL OR f.season_id = p_season_id)
      AND public.can_access_team(f.team_id)
    GROUP BY f.id, f.opponent, f.competition, f.venue, f.ground_name, f.ground_address, f.ground_postcode, f.kick_off
  )
  SELECT jsonb_build_object(
    'fixtures', COALESCE(jsonb_agg(jsonb_build_object(
      'fixture_id', fd.id,
      'opponent', fd.opponent,
      'competition', fd.competition,
      'venue', fd.venue,
      'ground_name', fd.ground_name,
      'ground_address', fd.ground_address,
      'ground_postcode', fd.ground_postcode,
      'kick_off', fd.kick_off,
      'available_count', fd.available_count,
      'unavailable_count', fd.unavailable_count,
      'no_response_count', fd.no_response_count,
      'available', COALESCE(fd.available, '[]'::jsonb),
      'unavailable', COALESCE(fd.unavailable, '[]'::jsonb),
      'no_response', COALESCE(fd.no_response, '[]'::jsonb)
    ) ORDER BY fd.kick_off DESC), '[]'::jsonb),
    'can_manage', v_can_manage,
    'player_stats', '[]'::jsonb
  ) INTO v_fixtures
  FROM fixture_data;

  RETURN v_fixtures;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_team_availability TO authenticated, anon;
