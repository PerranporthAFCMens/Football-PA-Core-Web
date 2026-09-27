# Football PA Core Change Control

Updated: 27 September 2026

## Purpose

This is the living **change and decision register** for Football PA Core.

Git history tells us what code changed. This file records **why it changed, what behaviour is intentional, what has actually been verified, and what must not be accidentally reverted**.

Every future chat or development session must read this file before changing existing behaviour.

Perranporth is the UX reference, but Core remains generic and configurable for every team.

## Mandatory change-control workflow

Before changing an existing feature:

1. Read this file, `HANDOVER.md`, and the relevant current code/database objects.
2. Search this register for the affected area and identify any existing change IDs.
3. Inspect the legacy Perranporth implementation when the feature previously worked there.
4. State whether the proposed change is:
   - a bug fix restoring intended behaviour
   - a deliberate product change
   - a refactor that must preserve behaviour
5. Make the smallest safe change.
6. Verify code, database persistence, smoke checks and deployment as relevant.
7. Update this register **in the same work session** with:
   - what changed
   - why
   - commit/migration references
   - verification status
   - anything that must not be undone
8. Do not mark a change VERIFIED merely because code compiled or a button exists. End-to-end user behaviour must be tested where the feature is workflow-sensitive.

### Status meanings

- **INTENTIONAL**: approved product behaviour. Do not change casually.
- **VERIFIED**: checked in code/data and through an appropriate functional test.
- **CODE/DB VERIFIED, E2E OPEN**: implementation exists, but the whole user flow has not yet been proven.
- **OPEN / BROKEN**: known issue. Do not describe it as fixed.
- **FROZEN REFERENCE**: preserve for comparison; do not develop it as the new source of truth.

## Current branch/deployment control point

As of 27 September 2026:

- repository: `PerranporthAFCMens/Football-PA-Core-Web`
- Supabase: `hennzggqaquevqgiucqn`
- production: `https://core.footballpa.com`
- customer Perranporth: `https://footballpa.com/Perranporth`
- legacy Perranporth reference: `https://perranporthafcmens.github.io/Perranporth/`

Current repository checkpoint:

- `main`: `a0b82495aeeba32ed575d30b51b707e95605b918`
- `dev`: `a0b82495aeeba32ed575d30b51b707e95605b918`
- branches were deliberately reconciled on 27 September after comparing the emergency recovery histories
- Vercel status for the reconciled head: success
- customer Perranporth is synced from the same functional recovery state; documentation-only reconciliation commits do not change customer behaviour

**main and dev are aligned at this checkpoint. Future work should still compare refs before changing behaviour, but do not preserve the old divergence as an intentional state.**

## Current critical Matchday state

Matchday remains the highest-priority area and is **not yet approved as stable end-to-end**.

The 26 September Culdrose match exposed regressions in behaviour that had existed in the old working Perranporth Matchday implementation. Event-level persistence and the backend lifecycle have now passed a rollback-only disposable-fixture simulation, but an authenticated browser/device end-to-end run is still required before Matchday is called fully ready.

### Live Culdrose snapshot verified 27 September

Fixture ID: `4e39d643-e7f9-46a3-89da-6e25adc978f7`

Live database currently shows:

- fixture status: completed
- fixture score: **RNAS Culdrose 2–3 Perranporth**
- match state: FULL-TIME
- match-state score: **2–3**
- match-state elapsed: 5400 seconds
- voting event: open

Current protected event feed:

1. **5' Alex Taylor goal**, assist Fin Stribley, Central box
2. **37' conceded**
3. **65' conceded**
4. **85' Tyreece Gallaway goal**, assist Alfie Cunningham
5. **89' Tom Goodman goal**, assist Luke Watson-Read

The event feed supports three Perranporth goals and two conceded goals, which aligns with the fixture score of 2–3 because Perranporth were away.

The Culdrose fixture score, match-state score and event feed are now aligned at **2–3**. The match-state score was reconciled on 27 September after verification against the fixture and protected event feed. Culdrose remains production data and must not be used as a destructive test fixture.

The Culdrose events are marked `server_protected`. Preserve them unless the user explicitly requests a factual correction.

## Intentional behaviour and regression register

| ID | Area | Intentional behaviour / decision | Why | Source / protection | Status |
|---|---|---|---|---|---|
| CC-001 | Product architecture | Core is one generic multi-team product. Perranporth is the UX reference, not a special fork. | Avoid team-specific code drift. | README/HANDOVER | **INTENTIONAL** |
| CC-002 | Legacy Perranporth | The old standalone Perranporth app is a behaviour/reference source only. Do not revive it as the data/source-of-truth app. | Known-working UX is useful; architecture is obsolete. | Legacy repo snapshot/reference | **FROZEN REFERENCE** |
| CC-003 | Team feature gating | Voting and Subs are shown only when enabled for that team. St Agnes intentionally has both disabled; Perranporth has both enabled. | Different clubs need different modules. | `team_features`, shared nav | **INTENTIONAL** |
| CC-004 | Navigation | Nav order is configurable per team via `team_settings.nav_order`. | Teams can prioritise different workflows. | 21 Sep nav-order work | **VERIFIED** |
| CC-005 | Access control | Database capability helpers are authoritative. Front ends should consume `get_team_access_context`, not invent separate role matrices. | Prevent UI/RLS mismatch. | `ACCESS-CONTROL.md` | **INTENTIONAL / VERIFIED** |
| CC-006 | Players/Training | `players.html` owns player admin and training attendance. `training.html` is only a compatibility redirect. | Avoid duplicate training surfaces. | HANDOVER | **INTENTIONAL** |
| CC-007 | Fixture sync | A removed fixture whose played date has passed must not be marked cancelled merely because it disappeared from Full-Time. Ignored updates stay ignored unless the proposal changes. | Prevent historic fixtures being corrupted. | `persist_fixture_sync_ignored_updates` | **INTENTIONAL / VERIFIED** |
| CC-008 | Starting lineup persistence | Reloading Match Centre must preserve each player's exact tactical slot. Never rebuild XI by `Object.values()` order. | That bug shuffled saved players on reload. | `d6deed7623f4f70705d930d796b6600d51c1aee1`, smoke guard `89c265...` | **VERIFIED, user-confirmed 25 Sep** |
| CC-009 | Historical XI vs live XI | Formal starting XI history and current tactical XI are separate. Tactical swaps/substitutions must not rewrite historical starters. | Starts/appearance stats must remain accurate. | migration `separate_current_xi_from_starting_lineup` | **INTENTIONAL / VERIFIED** |
| CC-010 | Lineup image sharing | Match Centre must provide Share lineup image and Preview image from the same saved XI/formation state. | Restores old Perranporth Matchday capability. | `3bbfd24...`, `67b6ffd...` smoke protection | **CODE VERIFIED; user E2E confirmation still worth retaining** |
| CC-011 | Availability → squad | Saved match squad is the Match Centre player pool. Availability Centre builds from players who answered Available. | One source of truth for matchday squad. | fixture availability migrations/RPCs | **INTENTIONAL / VERIFIED** |
| CC-012 | Squad sharing | Share Squad must save first, preserve picker order, and produce the agreed WhatsApp-style squad message. | Avoid mismatch between shared and saved squad. | `957d378...`, `840f55d...` | **VERIFIED** |
| CC-013 | Subs Tracker | Supports pre-match collection, saved-squad filtering, upcoming fixture first, direct fixture links, match/player views and payment links. | Preserve the real Perranporth collection workflow. | `bcc073b...`, `1c5426d...`, `e6578ea...` | **INTENTIONAL / VERIFIED** |
| CC-014 | Voting ballot | Ranked vote is 3/2/1, plus Dick of the Day. Successful submission shows confirmation and allows Change my vote without duplicate ballots. | Required player voting UX. | player portal / voting RPCs | **VERIFIED transactionally** |
| CC-015 | Voting candidates | When a saved match squad exists, voting candidates are restricted to that squad in both UI data and backend validation. | Players outside the match squad must not be voteable. | migration `restrict_player_voting_to_saved_match_squad` | **VERIFIED transactionally** |
| CC-016 | Voting Centre UX | Keep the familiar Perranporth management flow: match selector, OPEN/CLOSED, controls, link, Top 3, DOD, who's voted, still to vote. Season table is additional, not a replacement. | A redesign was explicitly rejected. | HANDOVER 21 Sep section | **INTENTIONAL** |
| CC-017 | Live Score | Public token-based spectator scoreboard; completed match remains available for the rest of that UK calendar day. | Matchday spectator requirement. | `team-scoreboard`, `live-score.html` | **INTENTIONAL / code verified** |
| CC-018 | Goal zones | Use the approved 10-zone half-pitch map. Do not revert to the earlier 8-zone full-pitch design. | Explicitly approved spatial model. | HANDOVER | **INTENTIONAL** |
| CC-019 | Match event editing | Existing match events must remain editable, including goal details, cards, opposition goals, substitutions and minute/stoppage time. | Restores legacy Perranporth correction workflow. | Match Centre event editor | **INTENTIONAL** |
| CC-020 | Goalscorer selection | Goal logging must require an explicit scorer. Never silently default to the first XI player. | Culdrose incident recorded Alex selection as Leo; first XI object order put Leo first. | `9a7c4d399851c5f2ef37ffed261d3c2fe0eccc18`; dev equivalent `09ac69c...` | **CODE VERIFIED, E2E OPEN** |
| CC-021 | Conceded goal | Match Centre must have an explicit **🥅 Conceded** action. It records `team_side='opponent'`, no player, and increments only the opposition score. | Missing during live Culdrose match. | `7b5480f6...`; dev `e7a4cf0...` | **CODE VERIFIED, E2E OPEN** |
| CC-022 | Two-half phase controls | Standard 11-a-side flow should read **Start Match → Half Time → Start Second Half → Full Time**. Preserve period-specific behaviour for formats such as St Agnes four-quarter games. | User expects football terminology and the old working flow. | `3aa0f670...`; smoke `209040dc...` | **CODE VERIFIED, E2E OPEN** |
| CC-023 | Match clock | Live clock is timestamp/anchor-based and must resynchronise after backgrounding/returning. Do not return to a fragile client-only one-second counter as authoritative time. | Phone backgrounding and autosaves caused confusing time behaviour. | migration `timestamp_anchored_match_clock`; commit `5d1d27a...` | **CODE/DB VERIFIED, E2E OPEN** |
| CC-024 | Event persistence safety | Server-corrected events can be `server_protected`; stale legacy payloads must not silently delete them. Current Match Centre no longer sends the whole event feed during runtime saves. | Recovery exposed whole-array autosave overwrite risk. | migrations `protect_server_corrected_match_events`, `event_level_matchday_persistence` | **VERIFIED guard; current browser migrated** |
| CC-025 | Event persistence architecture | Current Match Centre uses stable event/substitution IDs and event-level upsert/delete RPCs. Clock, phase and XI saves are separate and do not carry event history. `save_match_centre_state` remains as a legacy compatibility endpoint but is not called by the current Match Centre browser. | Prevent stale/open devices from replacing authoritative live event history. | migration `event_level_matchday_persistence`; dev `e6ca612b...`; smoke `626bc3d...`; production merge `3927a365...` | **CODE/DB/DEPLOYMENT VERIFIED; AUTH BROWSER E2E OPEN** |
| CC-026 | Voting at Full Time | Voting is intended to open **exactly once at Full Time**, not at match start and not merely because a confirmation dialog was shown. Current Match Centre completion persists through `save_match_runtime_state`, which opens voting server-side. | Automatic opening failed during Culdrose. | migrations `auto_open_voting_on_match_completion`, `restore_match_start_voting`, `open_voting_only_at_full_time`, `event_level_matchday_persistence` | **DB ROLLBACK FLOW + PRODUCTION CODE VERIFIED 27 SEP; BROWSER E2E OPEN** |
| CC-027 | Player Portal team context | Shared player portal/voting links must resolve the correct team from the portal token when team query context is absent. | Prevent voting link landing in wrong/unknown team context. | migration `resolve_player_portal_team_from_token`; commit `11644cb...` | **CODE/DB VERIFIED, E2E OPEN** |
| CC-028 | Culdrose recovery data | Current protected Culdrose event feed listed above is production data, not a disposable test. | Preserve recovered real-match history. | Supabase live snapshot 27 Sep | **INTENTIONAL DATA PROTECTION** |
| CC-029 | Auth signup branding | Core signup passes team ID/name, club name, badge and primary colour in Auth metadata. | Confirmation email must be team-aware. | `20357fb7...` | **DEPLOYED** |
| CC-030 | Auth email template | Hosted Supabase Confirm signup template must render team metadata with generic Football PA fallback. Hard-coded Harbour branding is wrong. | Multi-team product must not send another club's branding. | Dynamic HTML supplied; Supabase dashboard save still needs verification | **OPEN / NOT VERIFIED SAVED** |
| CC-031 | Auth redirect | Production confirmation links must not redirect to `http://localhost:3000`. | Invalid production confirmation destination. | Supabase Auth URL Configuration | **OPEN** |
| CC-032 | Perranporth customer path | `footballpa.com/Perranporth` is a synced customer copy of Core and must preserve its stable customer-facing URL. | Perranporth users should not be sent to dev/legacy URLs. | marketing sync workflow | **INTENTIONAL** |
| CC-033 | St Agnes QA | St Agnes is a real QA team: 7-a-side, four 12-minute periods, Voting and Subs intentionally hidden. | Ensures Core works beyond Perranporth. | Team config | **INTENTIONAL** |
| CC-034 | Football clock / stoppage-time semantics | Match events use configured football periods: normal minutes are 1-based, added time is stored separately as `minute` + `stoppage_minute` (for example 45 + 2), a new period restarts from its configured football-time boundary, and stoppage time must never inflate player-minute totals. Red cards stop that player's minutes. | Preserves the proven legacy Perranporth behaviour without the old `45.02` storage workaround and works for non-45-minute formats. | dev `3b99850...`, `8567502...`; migration `normalise_match_stoppage_player_minutes`; smoke `c0d08e2...` / `57abf48...` | **CODE/DB ROLLBACK VERIFIED; AUTH BROWSER E2E OPEN** |
| CC-035 | Goal-zone map by match format | 11-a-side uses the original Perranporth 11-zone goal/assist map. 7-a-side uses the 10-zone map. Match Centre capture, event editing and Dashboard reporting must derive the zone count from `teams.match_format` so they cannot drift apart. | Keeps Perranporth legacy analytics intact while preserving the correct small-sided model. | dev `18bd1f1...`, `8f167fa...`, smoke `5b6d75f...` | **CODE/SMOKE VERIFIED** |
| CC-034 | Match kit | Goalkeeper kit colour is separately configurable; keeper uses solid colour. Assist capture can be disabled and then assist UI must hide. | Per-team match configuration. | settings + Match Centre | **INTENTIONAL** |
| CC-035 | Branch handling | main/dev emergency divergence was reconciled deliberately on 27 September after comparing both histories. Keep branches aligned unless a future dev-only change intentionally requires divergence. | Prevent accidental branch drift while preserving reviewed recovery changes. | reconciliation commit `a0b82495...` | **VERIFIED / RECONCILED** |

## Current known open items

These are not optional polish. They are known risks or regressions that must remain visible:

1. **Matchday full-flow validation is incomplete.**
2. **Culdrose fixture score and match-state score were reconciled to 2–3 on 27 September.**
3. **Voting auto-open passed a clean rollback-only database flow test on 27 September, including repeated Full Time save without duplicate voting event. Browser E2E remains open.**
4. **Current Match Centre no longer uses whole-array event replacement. The legacy `save_match_centre_state` compatibility RPC still exists and should not be reintroduced into current browser code.**
5. **Confirm-signup email template still needs confirmation that the dynamic team-aware HTML was saved in Supabase.**
6. **Supabase Auth URL configuration still needs verification that localhost is gone.**
7. **Functional Matchday changes were developed on `dev` and merged to production through PR #1. Production functional merge is `3927a365...`; branch ancestry may differ by merge commits even when file content is aligned.**

## Matchday acceptance test required before next real match

Use a disposable/test fixture, never Culdrose.

The test must cover, in order:

1. Start Match
2. Verify clock starts and survives background/return
3. Log our goal with explicitly selected scorer
4. Add assist and zone
5. Reload and verify exact scorer/assist/minute
6. Log Conceded
7. Reload and verify score/event
8. Yellow card
9. Red card if safe in test
10. Single substitution
11. Multiple substitutions
12. Pause/resume
13. Half Time
14. Start Second Half
15. Add/edit/delete an event
16. Full Time
17. Verify fixture status/score and match-state score agree
18. Reload and verify exact event feed
19. Verify Live Score
20. Verify Voting opens exactly once
21. Verify Player Portal voting link resolves correct team
22. Verify voting candidate list equals saved match squad
23. Submit a test 3/2/1 + DOD ballot
24. Change that vote and verify no duplicate ballot

Only after all of these pass should Matchday be marked **VERIFIED** here.

### 27 September Matchday verification

- Reconciled the protected Culdrose `match_states` score to **2–3**, matching the completed fixture and five protected events.
- Ran a rollback-only disposable fixture simulation through the real `save_match_centre_state` RPC.
- Verified Start Match, explicit Alex Taylor goal at 5', conceded at 37', yellow card, substitution, Half Time, Second Half, final 2–3 score, FULL-TIME completion and automatic voting.
- Verified a repeated FULL-TIME save does **not** create a duplicate voting event.
- The transaction deliberately raised `MATCHDAY_TEST_PASS` and rolled back. Post-check confirmed zero test fixtures remained and the real Culdrose voting event stayed open.
- This is a backend/database flow verification, not a substitute for a browser/device end-to-end Matchday test.

### 27 September event-level persistence verification

- Applied Supabase migration `event_level_matchday_persistence`.
- Added stable event and substitution IDs to the Match Centre load path plus individual create/edit/delete RPCs.
- Split runtime persistence so clock, phase, formation and current XI save through `save_match_runtime_state` without sending or rewriting the event feed.
- Added match-event/substitution triggers so server scores and cross-device version timestamps update from persisted rows.
- Added a five-second remote-version check in Match Centre so another device's saved changes are reloaded instead of overwritten.
- Ran a second rollback-only disposable fixture test through the new RPCs. It verified event insert/update without duplication, conceded scoring, substitution insert/delete, runtime saves preserving events, Full Time voting opening exactly once, score recalculation after event delete and explicit reset.
- The test deliberately raised `MATCHDAY_EVENT_LEVEL_TEST_PASS` and rolled back. Post-check confirmed zero test fixtures and Culdrose remained FULL-TIME 2–3 with five protected events and one open voting event.
- JavaScript parse check passed for the updated Match Centre with no missing DOM IDs.
- Vercel production deployment for merge `3927a365f78ce89179e55832231d793deadde5db` is `READY` and aliases include `core.footballpa.com`.
- Restored legacy football-time semantics: first-half added time is stored/displayed as 45+N, second-half added time as 90+N for a 2x45 configuration, with the same rule derived from team-configured period lengths for other formats.
- Starting a new period now resets the football clock to the exact configured period boundary, so first-half stoppage does not leak into second-half minutes.
- Player-minute calculations now ignore stoppage-time additions, support repeated on/off intervals, and stop at a red card. Rollback-only test results: rolling + red = 42, off at 45+3 = 45, on at 45+3 then off at 83 = 38.
- An authenticated browser/device E2E remains required before calling the entire Matchday workflow fully closed.

## Recent emergency change chronology

### 25 September

- `d6deed7623f4f70705d930d796b6600d51c1aee1` — preserve saved lineup positions on reload
- `89c265be80563a51cb91e1e6d4e3d10323782e99` — protect lineup persistence in smoke checks
- `3bbfd24bba196f0ae0546edf88eb551e1c945260` — restore shareable lineup image
- `67b6ffd99746c5da061403f33d8ef98ced39b0ba` — protect lineup image sharing in smoke checks
- migration `restrict_player_voting_to_saved_match_squad`

### 26 September

- `20357fb7c342c41c2ffe022892734838ea57a24b` — pass team branding into Auth signup metadata
- `9a7c4d399851c5f2ef37ffed261d3c2fe0eccc18` — require explicit goalscorer selection
- `5d1d27a1adbda447439f19174d4e2a26b27163e8` — anchor match clock to timestamps
- `7b5480f6cd5660f5afefa60754a06cfefc3b7ed3` — restore conceded-goal action
- `11644cb50019ef4b5ca844ca6ea282ccdc9ad789` — resolve Player Portal team from portal token
- `3aa0f67093d9acb55170e9ea058184ddecd03b3e` — restore football Matchday flow
- `209040dcfb0e8a4158c7ccdde09d407561360f98` — protect Matchday controls in smoke checks

Relevant database migrations:

- `timestamp_anchored_match_clock`
- `protect_server_corrected_match_events`
- `resolve_player_portal_team_from_token`
- `auto_open_voting_on_match_completion`
- `restore_match_start_voting`
- `persist_match_clock_anchors`
- `open_voting_only_at_full_time`

A test-only migration `enable_pg_net_for_auth_email_test` also exists from investigation of the Auth email issue. Do not confuse it with a product requirement.

## How to add a new change

Append an entry to the register table or create a new subsection when the change needs more explanation.

Use this template:

```md
### CC-XXX — Short title

**Date:** YYYY-MM-DD  
**Area:** Matchday / Voting / Subs / Auth / etc.  
**Status:** INTENTIONAL / VERIFIED / CODE VERIFIED, E2E OPEN / OPEN  
**Reason:** Why this change exists.  
**Before:** Previous behaviour/problem.  
**After:** Intended behaviour.  
**Source:** Commit(s), migration(s), RPC/table if relevant.  
**Verification:** What was actually tested.  
**Do not regress:** The exact behaviour a future refactor must preserve.  
**Follow-up:** Any remaining work.
```

## Review checklist before merging/refactoring

Before changing existing code, answer all of these:

- Which CC IDs does this touch?
- Is the existing behaviour intentional or accidental?
- Did this behaviour already work in legacy Perranporth?
- Is there a user-confirmed workflow we must preserve?
- Does the change affect another team such as St Agnes?
- Does it alter data already recorded for real matches?
- Does it change Auth/RLS/capabilities?
- Does it change Match Centre state or event persistence?
- Does it require a migration?
- Does a smoke/integration check need adding?
- Have both main and dev branch differences been inspected?
- Has deployment been verified separately from the commit?
- Has this file been updated before declaring the work complete?

## Rule for future chats

A new chat must not infer intent solely from the latest code.

Read, in order:

1. `CHANGE-CONTROL.md`
2. `HANDOVER.md`
3. `CHAT-RESUME.md`
4. `ACCESS-CONTROL.md`
5. `CODE-AUDIT.md`
6. relevant source files and current database objects

If code and this register disagree, investigate the disagreement before changing anything. Do not silently “standardise” behaviour that may have been an intentional product decision.
