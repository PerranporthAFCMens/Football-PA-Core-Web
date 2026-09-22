# Code Audit and Deep-Clean Notes

Audit date: 21 September 2026

## Scope

Reviewed repository structure, shared context/navigation, Dashboard, Players, Training, Match Centre, Team Settings, Fixtures, fixture sync and smoke checks. Also reviewed current Match Centre persistence functions plus recent Supabase migrations and Edge Functions.

## Findings

### High priority

No unresolved high-priority persistence issue remains from this audit.

### Medium priority

- Players currently contains legacy/dead analytical and training code after recent navigation changes
- a second standalone Training implementation duplicates the combined Players/Training direction
- Team Settings still loads unused feature-state data after Features UI removal
- the goal-zone implementation is still the superseded eight-zone full-pitch version rather than the approved half-pitch map
- smoke checks do not yet cover several regressions already seen in testing
- Full-Time ground parsing remains best-effort

### Operational

Vercel build-rate limiting is the main reason the visible site can lag behind `main`.

## Cleanup completed

- `players.html` is now the single player-management/training-log surface
- `training.html` is a backwards-compatible redirect
- old Player Dashboard UI/state was removed from the Players surface
- temporary deployment marker removed
- unused Features fetch/state removed from Team Settings
- approved half-pitch goal map implemented
- duplicate shared-navigation mounts removed from Subs, Voting and Fixture Sync
- smoke checks expanded to cover the regressions above

## Deliberately retained

- `team_features` in shared context/navigation
- development/admin pages
- legacy/reference Supabase objects
- old static logo asset until usage is conclusively checked

Avoid broad rewrites solely for aesthetics. Clean around proven product boundaries and preserve working persistence paths.


## 21 September batch

- restored strong player-name sizing after the Players & Training cleanup
- Players defaults to surname A–Z and offers surname, shirt-number and first-name sorting
- added persistent Save & lock / Unlock workflow to training attendance, backed by a database write guard
- added tokenised public Live Score page and `team-scoreboard` Edge Function
- added Live Score to the authenticated navigation and spectator sharing


## 21 September follow-up

Additional completed cleanup and UX fixes:
- Match Centre period controls consolidated to one reversible Start/End period button
- saved starting lineup can be unlocked for corrections
- match-event zone save error fixed at the Supabase RPC layer because the database zone column is integer
- Dashboard mobile page overflow fixed
- Dashboard Player data table now scrolls internally with a sticky player-name column
- sticky Dashboard player names shortened to first name + surname initial
- Live Score and training-session locking are now part of the documented core product state

Resolved in the 21 September persistence follow-up:
- current tactical XI moved to `match_states.current_xi`
- routine autosaves no longer rewrite historical starter rows
- explicit starting-lineup saves use a dedicated RPC
- substitution feed entries are reconstructed after reload

Still unresolved:
- broader fixture/front-end permission alignment review


## Recommendation 1/5 — Core authorisation and RLS model

Implementation completed on `dev` on 21 September 2026. Production promotion is deliberately held until the GitHub Pages dev preview is runtime-checked.

Completed:

- added one database capability contract for team/club access
- added `get_team_access_context(team_id)` for frontend capability resolution
- aligned Core Context and shared navigation with the database contract
- aligned Match Centre, Players/Training, Fixtures, Fixture Sync, Team Settings, Voting and Subs management paths with their specific capabilities
- corrected team-only manager RLS so club, season and roster data resolve correctly
- aligned primary fixture, team settings, team features, player, training, match and voting-event RLS policies
- aligned Match Centre, Subs and Voting runtime RPC authorisation with the shared helpers
- aligned the FA Full-Time preview Edge Function with `can_manage_fixtures`
- documented the permanent contract in `ACCESS-CONTROL.md`
- expanded smoke checks so capability wiring is regression-tested

Database validation used simulated authenticated JWT contexts inside rolled-back transactions.

Verified:

- the existing Perranporth team-only manager now sees the required club, two seasons, 34 club players, 19 active roster players and 64 fixtures
- the same manager can manage Match Centre, Players, Fixtures, Voting and Subs
- a plain team member sees club/season/team context and the 19-player roster but receives no management capabilities
- a plain member cannot update a fixture
- a club owner with no team membership can manage the team
- a delegated `match` permission grants Match management without granting unrelated capabilities
- the Perranporth manager can retrieve Voting Centre and voting snapshot RPC output through the unified model
- newly introduced access helpers are not executable by the anonymous role

Do not begin Recommendation 2/5 until Recommendation 1/5 has passed the dev-preview runtime check and has been promoted/verified according to the normal release discipline.


## Recommendation 2/5 — Database integrity and RPC grants

Completed on 21 September 2026.

Supabase migration: `20260921184908_harden_database_integrity_and_rpc_grants`.

Changes:

- opted the project into explicit default grants for future public tables, sequences and functions rather than relying on automatic Data API exposure
- removed anonymous execution from `update_club_branding` and `dev_create_team`
- removed direct public/anon/authenticated execution from trigger-only functions `set_updated_at` and `prevent_locked_training_attendance_change`
- preserved anonymous execution for the nine Player Portal RPCs that intentionally form the public PIN-session API
- created a non-exposed `private` schema for integrity trigger functions
- added 12 integrity guards covering fixtures, team players, linked membership players, match lineups, match squads, match events, substitutions, training attendance, voting events, Subs payments, Subs match statuses and Player Portal credentials
- added a partial unique index preventing duplicate team/player roster links where `season_id` is null
- remapped imported 2025/26 goal-zone data from the old 11-zone numbering to the approved 10-zone Core model
- preserved every imported original goal zone as `details.legacy_goal_zone` before remapping
- tightened `match_events.zone` to allow only 1–10 or null

Validation:

- all checked cross-club/team/season relationships currently report zero mismatches
- an authenticated cross-club roster mutation is rejected by the new integrity guard
- valid authenticated training-attendance writes still work with the locked-session trigger protected from direct RPC execution
- Voting Centre writes still work after trigger-grant hardening
- anonymous Player Portal player discovery still returns the expected 19 Perranporth portal players
- anonymous `update_club_branding` execution is blocked
- no event remains with goal zone 11
- 151 imported historical goal zones were remapped and all 151 original values were retained in JSON
- Supabase Security Advisor now reports anonymous SECURITY DEFINER warnings only for the nine deliberately public Player Portal RPCs

The remaining authenticated SECURITY DEFINER warnings are the intentional signed-in Core RPC surface plus self-scoped authorisation helpers. They remain guarded inside the function bodies and will be revisited only if the API is later moved behind a dedicated exposed schema.


## Recommendation 3/5 — Eliminate GitHub Pages route escapes

Completed on 21 September 2026.

Changes:

- converted the Home dev-preview exit to a project-relative route
- converted Fixture Sync's Settings back-link to a project-relative route
- converted Player Portal auth/login and fallback navigation to project-relative routes
- converted the legacy Training redirect to a project-relative route
- fixed the default Login destination and email-confirmation callback so GitHub Pages retains the `/Football-PA-Core-Web/` project path
- converted all Dev Admin navigation and auth redirects across `dev.html`, `dev-login.html`, `dev-teams.html`, `dev-team.html` and `dev-create-team.html` to project-relative routes
- corrected stale smoke assertions that still expected the pre-Recommendation-1 `canManage` navigation model
- added an app-wide smoke rule that scans every root HTML file for unsafe root-relative HTML navigation, direct JavaScript root navigation and root-built callback URLs

Validation:

- 19 root HTML pages were scanned after the changes
- zero unsafe first-party root navigation matches remain
- all inline scripts across those pages parse successfully
- the smoke-check module parses successfully
- shared `ctx.href()` / `teamHref()` routes remain unchanged and continue to handle team domains plus GitHub Pages project hosting

The regression check now protects future pages too because it enumerates every root `.html` file at smoke-test time.


## Recommendation 4/5 — Extract shared frontend plumbing

Completed on 22 September 2026.

Scope was deliberately kept narrow to avoid redesigning or destabilising working football features.

Changes:

- added `core-client.js` as the single shared Supabase client bootstrap
- moved the Supabase project URL and publishable client creation out of 18 individual HTML pages
- wired all Core, Player Portal, Live Score and Dev Admin pages that use Supabase through `FootballPAClient`
- preserved all page-specific match, voting, subs, dashboard and admin logic in place
- added smoke checks that require Supabase-enabled pages to load `core-client.js`, reject page-local `supabase.createClient(...)` calls, and verify load order
- confirmed all affected inline scripts still parse successfully

This recommendation intentionally stops here. Further extraction of small helpers such as local escaping functions would add churn without meaningful structural benefit at this stage.


## Recommendation 5/5 — Harden public Player Portal and public team services

Completed on 22 September 2026.

Supabase migrations:

- `20260922110146_harden_player_portal_public_access`
- `20260922110427_fix_public_token_rotation`
- `20260922110635_lock_legacy_player_portal_mode`

Edge Function:

- `team-calendar` v2

Changes:

- added per-team `player_portal_token` capability links, defaulting to protected mode for new teams
- added token-protected Player Portal directory, login and first-time setup RPCs
- kept the original Perranporth PIN/DOB RPC signatures working behind an explicit Perranporth-only legacy compatibility flag
- locked `player_portal_legacy_open` so only a platform admin can change the exception
- added manager-controlled token rotation for Player Portal, Live Score and fixture calendar public links
- Player Portal token rotation also invalidates active portal sessions for that team
- added a Team Settings Public Links panel with copy/regenerate actions for all three public services
- updated Voting Centre and Dev Admin Player Portal links to include the protected portal token
- prevented ordinary Team Settings saves from spreading stale settings data back over newly rotated tokens
- confirmed Live Score remains exact-token-only and spectator-safe
- changed the public fixture calendar from a fixed 90-minute event duration to `period_count × period_minutes`
- added `PUBLIC-SURFACES.md` describing the permanent public-service security boundary
- expanded smoke checks for tokenised Player Portal entry, secure generated links and public-link management

Validation:

- Perranporth legacy Player Portal still returns its expected 19-player directory
- the protected Perranporth Player Portal link returns the same 19-player directory
- generic teams reject bare-team-ID legacy Player Portal discovery
- incorrect Player Portal tokens are rejected
- anonymous users see zero `team_settings` rows and cannot retrieve public capability tokens directly
- anonymous users cannot execute the public-token rotation RPC
- authenticated managers can rotate portal, scoreboard and calendar tokens
- non-platform managers cannot enable or disable legacy Player Portal compatibility
- the active `team-calendar` v2 source uses team-configured period count and period minutes
- Dynamos Girls U10 calendar duration now resolves to 48 minutes; adult 2 × 45 teams remain 90 minutes
- Player Portal, Team Settings, Voting Centre and Dev Admin changed pages all pass JavaScript syntax checks
- the public-service regression checks are present in `scripts/smoke-check.mjs`

This completes the five-recommendation Football PA Core technical audit and stabilisation pass.
