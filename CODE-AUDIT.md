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
