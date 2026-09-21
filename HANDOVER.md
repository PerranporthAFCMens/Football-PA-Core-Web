# Football PA Core Handover

Updated: 20 September 2026

## Project

Football PA Core is the generic multi-team version of Football PA. Perranporth is the UX reference only. Core must stay team-agnostic and configurable.

Repository: `PerranporthAFCMens/Football-PA-Core-Web`  
Supabase project: `hennzggqaquevqgiucqn`  
Primary domain: `https://core.footballpa.com`

Do not modify the separate live Perranporth app unless explicitly asked.

## Intended navigation

1. Home
2. Fixtures
3. Match Centre
4. Dashboard
5. Players & Training
6. Voting
7. Subs Admin
8. Settings

Dashboard sits directly below Match Centre with no special Dashboard heading.

## Dashboard

`dashboard.html` owns statistical/performance views: team KPIs, form, home/away split, goals for/against, scorers, assists, appearances, goal timing and player data including training attendance.

## Players & Training

`players.html` should be administrative, not analytical:
- add/edit/remove squad players
- shirt number and position
- create/review/delete training sessions
- attendance
- Select all attendance

`training.html` should remain only as a backwards-compatible redirect once the cleanup is complete.

## Current QA team

St Agnes, Dynamos Girls U10:
- team: `5337936a-5db7-4447-ac4a-d50323eb0715`
- season 2026/27: `f8ef6074-d483-4dd1-b15c-1957305469d3`
- 7-a-side
- four x 12 minute periods

There are five completed fixtures marked `Demo / Test` to populate dashboards.

## Match Centre

Current intended behaviour:
- match-format-specific formations
- configurable kit and shirt-number colour
- explicit Set starting lineup control
- single and bulk substitutions
- bulk incoming-player duplicate prevention
- goal logging with scorer, assist, goal type and spatial zones
- optional card controls
- fixture status uses `scheduled`, `live`, `completed`

### Approved goal-zone map

Use a half pitch. The approved map is the old Perranporth idea with old zones 2 and 3 combined:

1. Six-yard box
2. Central box: outside the six-yard box, inside the penalty area, aligned to the six-yard width
3. Left box
4. Right box
5. Left wide
6. Right wide
7. Edge of box
8. Left channel
9. Central build-up
10. Right channel

Do not revert to the earlier eight-zone full-pitch mock-up.

## Live Score

`live-score.html` is a spectator-safe scoreboard inspired by the Perranporth live page. It is linked from the authenticated nav but the shared URL is token-based and can be opened without signing in.

- public read-only Edge Function: `team-scoreboard`
- token: `team_settings.scoreboard_token`
- refreshes from Match Centre state every 5 seconds
- follows configured club branding
- shows team names, score, phase/time and our recorded scorers
- after full time, the completed fixture remains the selected scoreboard match for the rest of that UK calendar day
- Share uses native Web Share where available, with copy-link fallback

## Training session locking

Training attendance is still saved as it is changed, but a manager can now use **Save & lock session** as the final confirmation. Locked sessions disable attendance editing, Select all and deletion. Unlocking is explicit. The lock is persisted in `training_sessions.locked_at/locked_by`, and a database trigger rejects attendance writes to locked sessions.

## Fixtures

`fixtures.html` supports active-season fixtures, filters, manager add/edit, completed scores, ground details, directions and calendar subscription.

Full-Time sync uses `fixture-sync.html` and Edge Function `fa-fulltime-preview`. Ground/address extraction is best-effort because Full-Time detail HTML can vary.

Calendar subscriptions use Edge Function `team-calendar` and a per-team UUID token.

## Edge Functions

- `perranporth-matchday` v18
- `fa-fulltime-preview` v13
- `team-calendar` v1

## Feature flags

Features controls were removed from Team Settings. The underlying `team_features` table and shared gating support still exist deliberately for compatibility.

## Deployment warning

Vercel has repeatedly rejected builds with `build-rate-limit`. GitHub `main` can be ahead of the visible deployment. Check commit deployment status before assuming code is missing.

Do not create dummy deployment commits. Batch genuine changes.

## Critical technical risk found in the sweep

### Match lineup history is mutable

Current `save_match_centre_state` deletes and recreates `match_lineups` from the current on-pitch XI on every save. After substitutions this can overwrite the true starting lineup and make starts/appearances/minutes analytics inaccurate.

Recommended architecture:
- add `current_xi` to `match_states`
- make Set starting lineup write historical starter rows once
- never replace historical starter rows during normal autosaves
- load tactical XI from `match_states.current_xi`

Treat this as a dedicated persistence migration, not a cosmetic edit.

### Substitution feed after reload

Substitutions are stored in `substitutions`, while `rpcEvents()` excludes substitution events. On reload the substitution records survive, but the visible event feed is not rebuilt from them.

### Permission alignment

Front-end `canManage` can include club owner/admin, while some fixture RLS historically focused on team roles plus platform admin. If UI permits a write but RLS rejects it, compare both models before broadening access.

## Deep-clean status

Completed on main:
- durable README, handover, resume and audit docs added
- Players & Training rewritten as one focused management/attendance surface
- legacy Training route reduced to a redirect
- duplicate shared-navigation mounts removed from Subs, Voting and Fixture Sync
- dead Features loading removed from Team Settings
- temporary deploy marker removed from shared navigation
- approved half-pitch goal-zone map implemented
- smoke checks expanded around regressions already seen in testing

The remaining high-priority work is architectural rather than cosmetic: starting-lineup history/current-XI persistence and substitution-feed reconstruction.

## Validation discipline

Before calling a fix complete:
1. inspect the exact code/schema
2. make the real change
3. syntax-check JavaScript
4. check DOM references
5. run/update smoke checks
6. verify Supabase persistence where relevant
7. verify Vercel deployment separately
