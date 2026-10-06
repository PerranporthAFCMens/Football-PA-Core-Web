import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" }
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const service = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const body = await req.json().catch(() => ({}));
    const fixtureId = String(body.fixture_id || "");
    const playerIds = Array.isArray(body.player_ids)
      ? body.player_ids.map((id: any) => String(id || "")).filter((id: string) => id)
      : [];

    if (!fixtureId || !playerIds.length) {
      return json({ error: "fixture_id and player_ids (array) are required" }, 400);
    }

    // Verify fixture exists
    const { data: fixture, error: fixtureError } = await service
      .from("fixtures")
      .select("id")
      .eq("id", fixtureId)
      .single();

    if (fixtureError || !fixture) {
      return json({ error: "Fixture not found" }, 404);
    }

    // Delete existing lineup for this fixture
    await service.from("match_lineups").delete().eq("fixture_id", fixtureId);

    // Insert new confirmed lineup with position order
    const lineupRecords = playerIds.map((playerId, idx) => ({
      fixture_id: fixtureId,
      player_id: playerId,
      position_order: idx,
      created_at: new Date().toISOString()
    }));

    const { error: insertError } = await service
      .from("match_lineups")
      .insert(lineupRecords);

    if (insertError) {
      return json({ error: insertError.message }, 400);
    }

    return json({
      ok: true,
      message: "Starting lineup confirmed",
      count: playerIds.length
    });
  } catch (e) {
    return json(
      { error: e instanceof Error ? e.message : "Unable to confirm lineup" },
      500
    );
  }
});
