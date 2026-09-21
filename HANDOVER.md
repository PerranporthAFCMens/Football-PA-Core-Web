# Football PA Core Handover

Updated: 21 September 2026

## Project

Football PA Core is the generic multi-team version of Football PA. Perranporth is the UX reference only. Core must stay team-agnostic and configurable.

Repository: `PerranporthAFCMens/Football-PA-Core-Web`  
Supabase project: `hennzggqaquevqgiucqn`  
Primary domain: `https://core.footballpa.com`

Do not modify the separate live Perranporth app unless explicitly asked.

## Intended navigation

The shared navigation is team-aware and feature-aware.

Always/common:
1. Home
2. Match Centre, when enabled
3. Players, when enabled
4. Fixtures
5. Dashboard
6. Live Score, when configured
7. Settings, for managers/admins

Conditional manager/admin tools:
- Voting appears when `team_features.voting=true`
- Subs Tracker appears when `team_features.subs_finance=true`

For example, Perranporth has both Voting and Subs Tracker enabled, while St Agnes has both disabled, so their menus are intentionally different.

## Dashboard

`dashboard.html` owns statistical/performance views: team KPIs, form, home/away split, goals for/against, scorers, assists, appearances, goal timing and player data including training attendance.

Current mobile behaviour:
- page-level horizontal overflow has been removed
- only the Player data table scrolls horizontally
- the Player column is sticky
- sticky player names use first name + surname initial, for example `Olivia T.`
- the sticky Player column is deliberately narrow so more statistics remain visible

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
- starting lineup can be saved, then explicitly unlocked with **Edit starting lineup** if a correction is needed
- one period control button changes state: **Start Period 1 → End Period 1 → Start Period 2 → End Period 2**, continuing for all configured periods
- Pause remains a separate control
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

Full-Time disappearance rules:
- if a fixture disappears from Full-Time after its scheduled calendar date has passed, do not treat that disappearance as a cancellation/update
- future fixtures that disappear can still be offered as a possible cancellation
- ignored sync updates are persisted in `team_settings.fixture_sync_ignored_updates`
- an ignored update stays hidden unless the proposed change itself later changes
- the Home fixture-update notice uses the same ignore and past-fixture rules

Calendar subscriptions use Edge Function `team-calendar` and a per-team UUID token.

## Edge Functions

- `perranporth-matchday` v18
- `fa-fulltime-preview` v13
- `team-calendar` v1
- `team-scoreboard` public read-only scoreboard endpoint

## Feature flags

Features controls were removed from Team Settings. The underlying `team_features` table and shared gating support still exist deliberately for compatibility.

## Deployment warning

Vercel previously hit `build-rate-limit` repeatedly. Recent deployments have been succeeding again, but GitHub `main` can still be ahead of the visible deployment if a build fails. Always check commit deployment status before assuming code is missing.

Do not create dummy deployment commits. Batch genuine changes when sensible.

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
- player names restored to stronger sizing after over-cleaning
- Players defaults to surname A–Z with surname, shirt-number and first-name sorting
- training sessions support persistent Save & lock / Unlock
- legacy Training route reduced to a redirect
- duplicate shared-navigation mounts removed from Subs, Voting and Fixture Sync
- dead Features loading removed from Team Settings
- temporary deploy marker removed from shared navigation
- approved half-pitch goal-zone map implemented
- Live Score page, nav entry and sharing added
- Match Centre period controls consolidated into one Start/End button
- saved starting lineup can be unlocked and corrected
- Dashboard mobile overflow fixed
- Dashboard Player data uses a narrow sticky first-name + surname-initial column
- smoke checks expanded around regressions already seen in testing

The starting-lineup/current-XI persistence split and substitution-feed reconstruction are now complete. The next architectural review area is broader fixture/front-end permission alignment.

## Validation discipline

Before calling a fix complete:
1. inspect the exact code/schema
2. make the real change
3. syntax-check JavaScript
4. check DOM references
5. run/update smoke checks
6. verify Supabase persistence where relevant
7. verify Vercel deployment separately


## Important Supabase fix applied on 21 September

`match_events.zone` is an integer column. Match Centre had been sending text such as `"Zone 1"`, which caused save failures. The database function `save_match_centre_state` was updated so it safely extracts and stores the numeric zone.

This database fix was applied directly through a Supabase migration and does not require a front-end deployment.


## Perranporth Core migration — 21 September 2026

Perranporth AFC has been provisioned in the shared Core/Supabase platform as a normal configurable club/team rather than a special fork.

Migration scope:
- Perranporth club + Men's 1st Team, 2026/27
- current squad, fixtures, match events, substitutions, starter history, voting and subs/payment history
- 2025/26 historical fixtures/events plus player season snapshots for portal comparison
- £3 per-game subs configuration and existing Perranporth payment-link template
- platform/admin access for existing Supabase users; pending team-access claims for legacy managers who have not created a Supabase account yet
- generic legacy-compatible Player Portal PIN sessions, first-time DOB setup, PIN change and in-portal voting

The existing public Perranporth Player Portal URL must remain stable:
`https://PerranporthAFCMens.github.io/Perranporth/player.html`

Do not cut that legacy URL over until the Core production Player Portal has been deployed and verified for the Perranporth team. The compatibility page can then host the Core portal while preserving the original URL.

Perranporth remains a UX reference. Core should retain its generic multi-team architecture while adopting stronger Perranporth UX patterns where appropriate.


## Team subdomains — 21 September 2026

Football PA supports team-scoped hostnames through `public.team_domains`.

- `perranporth.footballpa.com` maps directly to Perranporth 1st Team.
- A mapped hostname takes precedence over query-string and local-storage team selection.
- Navigation on a team hostname stays on that hostname without `?team=...`.
- The login page reads only the public routing/branding directory and brands itself before authentication.
- Dev Admin Create/Manage Team includes a Football PA subdomain field.
- `core.footballpa.com` remains the generic Core entry point.
- DNS/Vercel domain assignment is infrastructure configuration and must be completed before a new hostname resolves publicly.


## Per-team navigation ordering — 21 September 2026

Each team can control the order of its available navigation items from Team Settings → Navigation Bar.

- Order is stored in `team_settings.nav_order`.
- Feature flags still control whether an item is available at all.
- Voting only appears when `team_features.voting=true`.
- Subs Tracker only appears when `team_features.subs_finance=true`.
- Live Score only appears when a scoreboard token is configured.
- The settings screen only presents the items that can actually appear for that team.
- Reordering uses mobile-friendly up/down controls.


## Goalkeeper kit colour — 21 September 2026

Team Settings → Match Kit includes a separate goalkeeper colour.

- Stored in `team_settings.goalkeeper_kit_colour`.
- Goalkeeper shirts in Match Centre are always rendered as a solid block colour.
- Outfield shirt pattern/colours remain unchanged.
- The goalkeeper is determined by the formation's `gk` slot, so tactical player changes do not change the kit rule.
- Goalkeeper shirt-number colour is chosen automatically for contrast.


## Team-subdomain navigation fix — 21 September 2026

The shared navigation resolves the active team from `team_domains` when running on a mapped team hostname.

This is required for clean URLs such as `perranporth.footballpa.com`, where there may be no `?team=` query parameter.

- mapped hostname → team ID
- feature flags are loaded for that team
- Voting/Subs gating therefore works on clean team subdomains
- links remain on the team hostname without adding `?team=`
- generic Core/dev URLs still use explicit team query parameters


## Shared visual refresh — 21 September 2026

Core now uses a slightly richer shared visual language without changing page architecture.

- cards use softer team-tinted surfaces, larger radii and more consistent elevation
- buttons/forms/tabs have consistent touch sizing and states
- Home is structured as Next Match → Season at a glance → Quick actions → Recent results / Coming up
- Training Log and Dashboard are proper shortcut tiles rather than plain text links
- the shared team header/menu styling is slightly refined while retaining team colours
- functional layouts such as Match Centre pitch, dashboard tables and settings forms were deliberately not structurally rewritten


## Football-focused visual refresh — 21 September 2026

The v5 visual layer deliberately moves away from a clinical SaaS feel.

- stronger club-colour use
- chunkier shortcut cards and controls
- matchday/football visual cues
- asymmetrical decorative shapes and stronger shadows
- more personality in results, stats and navigation
- still generic across clubs because all accents derive from each club's configured colours
- avoids structural changes to functional screens


## Header layout + reliable dev preview — 21 September 2026

The team header now follows the same spatial direction as the drawer:
- hamburger/menu trigger on the left
- club/team identity on the right
- club badge at the far right
- left-side drawer unchanged

The dev Pages workflow now triggers directly on every push to `dev`, checks out the exact pushed SHA, runs the smoke checker on that exact commit, and only then publishes the preview. This replaces the previous indirect `workflow_run` trigger which could leave the visible preview behind the current dev branch.


### Dev Pages deployment note
GitHub Pages currently restricts the deployment environment to the default branch. The supported preview pattern is therefore: a successful `dev` smoke run triggers the `Dev preview` workflow from `main`, and that workflow explicitly checks out `dev` before publishing. Do not add a direct `push: dev` Pages deployment unless the environment protection rule is changed first.
