# Code Audit and Deep-Clean Notes

Audit date: 20 September 2026

## Scope

Reviewed repository structure, shared context/navigation, Dashboard, Players, Training, Match Centre, Team Settings, Fixtures, fixture sync and smoke checks. Also reviewed current Match Centre persistence functions plus recent Supabase migrations and Edge Functions.

## Findings

### High priority

**Match lineup history is overwritten by autosave.**  
`save_match_centre_state` deletes and recreates `match_lineups` from the current XI. This is unsafe for historical starts/minutes after substitutions.

### Medium priority

- substitution feed is not reconstructed after reload
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
