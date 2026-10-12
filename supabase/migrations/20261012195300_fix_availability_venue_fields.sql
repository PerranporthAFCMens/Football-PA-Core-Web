-- Availability poll: return ground_name / ground_address / ground_postcode from fixtures
-- (previously only `venue` home/away was returned, so the UI showed "Venue TBC").
-- No-response is derived from the active team roster, because
-- fixture_availability_responses only holds rows for players who have replied.

CREATE OR REPLACE FUNCTION public.get_team_availability(p_team_id uuid, p_season_id uuid DEFAULT NULL)
RETURNS jsonb AS $$
DECLARE
  v_can_manage boolean;
  v_result jsonb;
BEGIN
  v_can_manage := public.can_manage_team(p_team_id);

  WITH roster AS (
    SELECT DISTINCT p.id AS player_id, p.display_name, p.shirt_number
    FROM public.team_players tp
    JOIN public.players p ON p.id = tp.player_id
    WHERE tp.team_id = p_team_id AND tp.active
      AND (p_season_id IS NULL OR tp.season_id = p_season_id)
  ),
  fx AS (
    SELECT f.*
    FROM public.fixtures f
    WHERE f.team_id = p_team_id
      AND (p_season_id IS NULL OR f.season_id = p_season_id)
      AND public.can_access_team(f.team_id)
  ),
  grid AS (
    SELECT fx.id AS fixture_id, ro.player_id, ro.display_name, ro.shirt_number, r.available
    FROM fx
    CROSS JOIN roster ro
    LEFT JOIN public.fixture_availability_responses r
      ON r.fixture_id = fx.id AND r.player_id = ro.player_id
  ),
  agg AS (
    SELECT g.fixture_id,
      count(*) FILTER (WHERE g.available IS TRUE) AS available_count,
      count(*) FILTER (WHERE g.available IS FALSE) AS unavailable_count,
      count(*) FILTER (WHERE g.available IS NULL) AS no_response_count,
      COALESCE(jsonb_agg(jsonb_build_object('player_id', g.player_id, 'name', g.display_name, 'shirt_number', g.shirt_number) ORDER BY g.display_name) FILTER (WHERE g.available IS TRUE), '[]'::jsonb) AS available,
      COALESCE(jsonb_agg(jsonb_build_object('player_id', g.player_id, 'name', g.display_name, 'shirt_number', g.shirt_number) ORDER BY g.display_name) FILTER (WHERE g.available IS FALSE), '[]'::jsonb) AS unavailable,
      COALESCE(jsonb_agg(jsonb_build_object('player_id', g.player_id, 'name', g.display_name, 'shirt_number', g.shirt_number) ORDER BY g.display_name) FILTER (WHERE g.available IS NULL), '[]'::jsonb) AS no_response
    FROM grid g
    GROUP BY g.fixture_id
  )
  SELECT jsonb_build_object(
    'fixtures', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'fixture_id', fx.id,
        'opponent', fx.opponent,
        'competition', fx.competition,
        'venue', fx.venue,
        'ground_name', fx.ground_name,
        'ground_address', fx.ground_address,
        'ground_postcode', fx.ground_postcode,
        'kick_off', fx.kick_off,
        'available_count', COALESCE(a.available_count, 0),
        'unavailable_count', COALESCE(a.unavailable_count, 0),
        'no_response_count', COALESCE(a.no_response_count, 0),
        'available', COALESCE(a.available, '[]'::jsonb),
        'unavailable', COALESCE(a.unavailable, '[]'::jsonb),
        'no_response', COALESCE(a.no_response, '[]'::jsonb)
      ) ORDER BY fx.kick_off DESC)
      FROM fx LEFT JOIN agg a ON a.fixture_id = fx.id
    ), '[]'::jsonb),
    'can_manage', v_can_manage,
    'player_stats', '[]'::jsonb
  ) INTO v_result;

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_team_availability TO authenticated, anon;
