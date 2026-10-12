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
  -- Check if user can manage this team
  v_can_manage := public.can_manage_team(p_team_id);

  -- Build fixtures array with availability data
  SELECT jsonb_build_object(
    'fixtures', COALESCE(jsonb_agg(jsonb_build_object(
      'fixture_id', f.id,
      'opponent', f.opponent,
      'competition', f.competition,
      'venue', f.venue,
      'ground_name', f.ground_name,
      'ground_address', f.ground_address,
      'ground_postcode', f.ground_postcode,
      'kick_off', f.kick_off,
      'available_count', COALESCE(COUNT(*) FILTER (WHERE a.response = true), 0),
      'unavailable_count', COALESCE(COUNT(*) FILTER (WHERE a.response = false), 0),
      'no_response_count', COALESCE(COUNT(*) FILTER (WHERE a.response IS NULL), 0),
      'available', COALESCE(jsonb_agg(
        jsonb_build_object('player_id', p.id, 'name', p.name, 'shirt_number', p.shirt_number)
        ORDER BY p.name
      ) FILTER (WHERE a.response = true), '[]'::jsonb),
      'unavailable', COALESCE(jsonb_agg(
        jsonb_build_object('player_id', p.id, 'name', p.name, 'shirt_number', p.shirt_number)
        ORDER BY p.name
      ) FILTER (WHERE a.response = false), '[]'::jsonb),
      'no_response', COALESCE(jsonb_agg(
        jsonb_build_object('player_id', p.id, 'name', p.name, 'shirt_number', p.shirt_number)
        ORDER BY p.name
      ) FILTER (WHERE a.response IS NULL), '[]'::jsonb)
    ) ORDER BY f.kick_off DESC), '[]'::jsonb),
    'can_manage', v_can_manage,
    'player_stats', '[]'::jsonb
  ) INTO v_fixtures
  FROM public.fixtures f
  LEFT JOIN public.fixture_availability a ON a.fixture_id = f.id
  LEFT JOIN public.players p ON p.id = a.player_id AND p.roster_active = true
  WHERE f.team_id = p_team_id
    AND (p_season_id IS NULL OR f.season_id = p_season_id)
    AND public.can_access_team(f.team_id)
  GROUP BY f.id, f.opponent, f.competition, f.venue, f.ground_name, f.ground_address, f.ground_postcode, f.kick_off;

  RETURN v_fixtures;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_team_availability TO authenticated, anon;
