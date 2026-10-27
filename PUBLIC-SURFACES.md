# Football PA Core Public Surfaces

Updated: 22 September 2026

This document describes the parts of Football PA Core that intentionally work without a normal Football PA sign-in.

## Player Portal

Generic Player Portal entry is protected by an unguessable per-team `player_portal_token`.

The share URL is:

`https://core.footballpa.com/player-portal.html?team=<team_uuid>&pin=1&portal=<player_portal_token>`

Pre-authentication RPCs for generic teams require both the team ID and the portal token:

- `player_portal_list_players_v2`
- `player_portal_login_v2`
- `player_portal_first_time_setup_v2`

After a successful PIN login, access moves to the existing random Player Portal session token. Stats, Subs, voting, PIN changes and logout remain session-token based.

A bare team UUID is not enough to enumerate the Player Portal directory for generic teams.

### Perranporth compatibility

Perranporth retains the original public PIN/DOB workflow because the established external Player Portal URL must remain stable.

This is controlled by `team_settings.player_portal_legacy_open`.

Only the Perranporth 1st Team is currently enabled for legacy mode. The flag defaults to false for all new teams, and a database trigger allows only a platform admin to change it.

The protected tokenised Core link also works for Perranporth and should be preferred for new sharing.


## Guest voting link

`guest-vote.html?t=<voting_events.public_token>` lets someone without a Football PA login or Player Portal PIN vote for one match.

- The token is a random UUID created by a signed-in manager (`voting_guest_link`) for one voting event. A manager can replace it, which stops the old link working.
- Guests use two pre-authentication RPCs only: `guest_vote_data` and `guest_vote_submit`. Both are keyed by the token; neither exposes team or player directories beyond the names the guest may vote for.
- The guest gives a name. One ballot is kept per name, so voting again with the same name changes that vote. Guest ballots are stored in `voting_ballots` with `voter_key = 'guest:<name>'` and are counted by the existing results.
- Voting rules match the Player Portal: three different players for 3, 2 and 1 points, one optional Dick of the Day with a reason. The names offered follow the game's saved squad, or the active team players when no squad is saved.
- The link only works while the voting event is open.

## Public link rotation

Team managers can rotate public capability links through the protected `rotate_team_public_token(team_id, kind)` RPC.

Supported kinds:

- `portal`
- `scoreboard`
- `calendar`

The RPC requires Core team-management permission.

Rotating the Player Portal token also deletes active Player Portal sessions for that team so an old shared link and any sessions created from it can no longer continue.

Anonymous users cannot execute the rotation RPC.

Team Settings exposes copy and regenerate controls for all three public links.

## Live Score

Live Score remains a public spectator service protected by `team_settings.scoreboard_token`.

The Edge Function looks up the team by exact token and then returns only the spectator-safe scoreboard payload:

- club/team branding
- selected fixture
- score
- phase and clock state
- our named scorers

It does not accept a team ID as an alternative to the token.

The token is not anonymously readable from `team_settings`.

## Fixture calendar

Fixture calendar access remains protected by `team_settings.fixture_calendar_token`.

The Edge Function resolves a calendar only by exact token and returns the configured team's current-season fixtures.

Calendar event duration now uses:

`period_count × period_minutes`

rather than a fixed 90 minutes.

Current examples:

- Dynamos Girls U10: 4 × 12 = 48 minutes
- Perranporth 1st Team: 2 × 45 = 90 minutes
- Harbour Athletic First Team: 2 × 45 = 90 minutes

## Security boundary

These tokens are capability links. Anyone who has a valid link can access the deliberately public content behind that link.

They should therefore be treated like share links, not passwords. If a link is shared too widely, regenerate it in Team Settings.

The underlying token values are protected by RLS from anonymous table access.

Do not add a new anonymous Core RPC without documenting its purpose here and adding an explicit regression check.
