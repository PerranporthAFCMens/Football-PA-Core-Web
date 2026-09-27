# Resume Football PA Core in a new chat

Paste this into a new conversation:

---

Continue work on the existing **Football PA Core** project after the live Matchday incident on **26 September 2026**.

Repository: `PerranporthAFCMens/Football-PA-Core-Web`  
Supabase project: `hennzggqaquevqgiucqn`  
Production: `https://core.footballpa.com`  
Customer Perranporth: `https://footballpa.com/Perranporth`

## Read these first

Before changing anything, read the current versions of:

- `CHANGE-CONTROL.md` **first**
- `README.md`
- `HANDOVER.md`
- `CODE-AUDIT.md`
- `ACCESS-CONTROL.md`
- `CHAT-RESUME.md`
- `scripts/smoke-check.mjs`

Treat `CHANGE-CONTROL.md` as the authoritative product-intent/regression register, then use the **26 September Emergency Matchday Handover** section in `HANDOVER.md` for incident detail.

## Current refs

Current functional production checkpoint:

- production `main` Matchday merge: `3927a365f78ce89179e55832231d793deadde5db`
- event-level browser persistence originated on `dev`: `e6ca612b0132d53e7c0d71fd0752b819844aad65`
- regression smoke protection: `626bc3d258c8b0e7b0c6127cc4fe9a29155203aa`
- production was merged through PR #1
- Vercel deployment `dpl_59sZoeQW3kECF6Qu1PrDkx9UzpXR` for `3927a365...` is `READY` and serves `core.footballpa.com`
- `dev` may contain newer documentation/control commits and branch ancestry may differ by merge commits even when functional files match

Before changing code, fetch and compare both refs. Do not infer drift from an old handover SHA.

## Absolute priority

**Matchday is the only priority until it is proven stable end-to-end. Do not start new product features.**

The user used Match Centre live against RNAS Culdrose and found regressions that should never have been lost from the old working Perranporth Matchday flow.

The requirement is:

> Preserve/rebuild the known-working Perranporth Matchday behaviour in Core. Do not redesign the workflow from scratch.

Inspect the legacy Perranporth Matchday implementation before changing Core again.

## What failed in the live Culdrose match

During the real match the user reported:

- a goal selected for **Alex Taylor** was initially recorded/displayed as **Leo Osborne**
- match minute behaviour was confusing/wrong during recovery
- there was no usable **Conceded** control when needed
- the Start/Half Time/Full Time flow did not match the old working Matchday experience
- player voting did not open automatically at Full Time when expected

The user is understandably frustrated by repeated regressions and by fixes being declared complete before a full Matchday flow is actually tested.

## Current emergency fixes already present

Current production code/database now includes:

- goalscorer must be explicitly selected, no silent first-XI default
- **🥅 Conceded** action
- two-half button labels:
  - Start Match
  - Half Time
  - Start Second Half
  - Full Time
- timestamp/anchor-based match clock
- clock resync when returning to the app
- server-protected recovered events so stale legacy payloads cannot silently wipe them
- **event-level Matchday persistence**: stable event/substitution IDs, individual create/edit/delete RPCs, and runtime clock/XI saves that do not carry the event feed
- server-side score recalculation from persisted goal rows
- five-second cross-device version checking so remote Matchday changes are reloaded instead of replaced
- Matchday smoke guards for conceded/scorer/phase controls and event-level persistence
- Player Portal resolves team context from the portal token
- database auto-open voting logic at match completion through `save_match_runtime_state`

Relevant recent migrations include:

- `timestamp_anchored_match_clock`
- `protect_server_corrected_match_events`
- `resolve_player_portal_team_from_token`
- `auto_open_voting_on_match_completion`
- `restore_match_start_voting`
- `persist_match_clock_anchors`
- `open_voting_only_at_full_time`
- `event_level_matchday_persistence`

Important: these changes are **not yet a substitute for an end-to-end Matchday test**.

## Voting nuance

Current Match Centre completion persists through `save_match_runtime_state`. When the fixture becomes completed, that RPC calls `set_voting_open_event(..., true)` provided Voting is enabled and the user has Voting management capability.

The Match Centre front end asks:

`Finish the match and open player voting?`

That confirmation text alone does not open voting. The server-side runtime save does it.

A rollback-only disposable fixture test on 27 September verified that Full Time opens voting and a repeated Full Time save does not create a duplicate event. Authenticated browser/device E2E remains open.

## Culdrose production data must be preserved

Fixture ID:

`4e39d643-e7f9-46a3-89da-6e25adc978f7`

Reverified in live Supabase on 27 September:

- RNAS Culdrose 1st v Perranporth
- Away
- completed
- fixture score **2–3**
- match state **FULL-TIME**
- match-state score **2–3**
- elapsed 5400 seconds
- voting event **open**

Protected events:

1. **5' Alex Taylor goal**, assist Fin Stribley, Central box
2. **37' conceded**
3. **65' conceded**
4. **85' Tyreece Gallaway goal**, assist Alfie Cunningham
5. **89' Tom Goodman goal**, assist Luke Watson-Read

Fixture score, match-state score and protected event feed are currently aligned at **2–3**. Preserve this recovered production state.

The recovered event rows are `server_protected`.

Do not alter/delete them or use Culdrose as a destructive test fixture unless the user explicitly asks.

Do not create another Culdrose voting event.

## Event-level persistence is now the current architecture

Current `match-centre.html` does **not** call `save_match_centre_state`.

It loads stable database IDs and uses:

- `upsert_match_event`
- `delete_match_event`
- `upsert_match_substitutions`
- `delete_match_substitution`
- `save_match_runtime_state` for phase/clock/formation/current XI only
- `reset_match_centre_state` only for an explicit destructive reset

`save_match_centre_state` remains only as a legacy compatibility endpoint. Do not reconnect current Match Centre to it.

A rollback-only database test passed create/edit/delete, conceded scoring, substitutions, Half Time/Second Half, runtime saves preserving events, Full Time voting exactly once, score recalculation and reset. The updated Match Centre JavaScript also parsed cleanly with no missing DOM IDs. Authenticated browser/device E2E is still required.

## What to do first in this new chat

Review the relevant `CHANGE-CONTROL.md` IDs before editing existing behaviour.

Do this in order:

1. Fetch current `main`, current `dev`, and read `CHANGE-CONTROL.md` first.
2. Do **not** repeat the legacy parity audit or event-level persistence redesign unless new evidence shows a regression. Those were completed on 27 September.
3. Use a disposable/test fixture, not Culdrose, and run the current production Match Centre in an authenticated browser/device session:
   - Start Match
   - our goal with scorer, assist and zone
   - conceded goal
   - cards
   - single sub
   - bulk subs
   - pause/resume
   - background/return
   - Half Time
   - Start Second Half
   - verify a second signed-in device sees event changes without overwriting them
   - Full Time
   - correct final score/status
   - exact event reload
   - Live Score
   - voting auto-opens exactly once
   - player voting link opens correct team and correct saved-squad candidates
4. Check Supabase state after each critical transition.
5. Add smoke/integration protection for any browser-only regression found.
6. Only then call Matchday fully ready.

## Secondary issue after Matchday

The Supabase **Confirm signup** email template is still hard-coded to Harbour United.

Core now passes team branding metadata into Auth, and a full dynamic replacement HTML template was supplied to the user.

When Matchday is stable, verify:
- Authentication → Email Templates → Confirm signup uses the dynamic template
- Auth URL Configuration no longer redirects confirmations to `http://localhost:3000`

Do not go back to the GitHub/Supabase personal-access-token workaround unless explicitly requested.

## Working style

- Use connected GitHub and Supabase tools directly.
- Verify actual code, DB state, smoke checks and deployment before saying something is fixed.
- Do not make the user repeat known project context.
- British English.
- Avoid em dashes.
- Preserve Perranporth behaviour while keeping Core generic/configurable.

---
