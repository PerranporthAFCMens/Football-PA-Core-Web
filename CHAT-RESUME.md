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

- `README.md`
- `HANDOVER.md`
- `CODE-AUDIT.md`
- `ACCESS-CONTROL.md`
- `CHAT-RESUME.md`
- `scripts/smoke-check.mjs`

Treat the **26 September Emergency Matchday Handover** section in `HANDOVER.md` as the authoritative continuation point for Matchday.

## Current refs

At handover creation:

- production `main`: `441708b8269aa47eb0fc2455d4c939656e9dfc4a`  
  - application code immediately before docs update: `209040dcfb0e8a4158c7ccdde09d407561360f98`
- `dev`: `c973ac1b8d6f1f72c8090d182d567bf0ac0df2e2`
  - application code immediately before docs update: `b9540cf99f9dc38055e919fff1c9d95d3b3a0327`

**main and dev are intentionally divergent right now. Do not blindly merge or fast-forward them.** Compare first and reconcile deliberately.

The production application commit `209040dc...` had:
- Core smoke checks: success
- Vercel: success
- Perranporth customer sync source: `209040dc...`

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
- server-protected recovered events so stale browser state cannot silently wipe them
- Matchday smoke guards for conceded/scorer/phase controls
- Player Portal resolves team context from the portal token
- database auto-open voting logic at match completion

Relevant recent migrations include:

- `timestamp_anchored_match_clock`
- `protect_server_corrected_match_events`
- `resolve_player_portal_team_from_token`
- `auto_open_voting_on_match_completion`
- `restore_match_start_voting`
- `persist_match_clock_anchors`
- `open_voting_only_at_full_time`

Important: these changes are **not yet a substitute for an end-to-end Matchday test**.

## Voting nuance

Current `save_match_centre_state` now calls `set_voting_open_event(..., true)` when a fixture becomes completed, provided Voting is enabled and the user has Voting management capability.

The Match Centre front end asks:

`Finish the match and open player voting?`

That confirmation text alone does not open voting. The database save RPC now does it.

This was added after the failure. Test it cleanly on a disposable/test fixture before saying it works.

## Culdrose data is now authoritative and must be preserved

Fixture ID:

`4e39d643-e7f9-46a3-89da-6e25adc978f7`

Current Supabase state:

- RNAS Culdrose 1st v Perranporth
- Away
- completed
- final score **2–2**
- state **FULL-TIME**
- 5400 elapsed seconds

Events:

1. **5' Alex Taylor goal**, assist Fin Stribley, Central box
2. **37' conceded**
3. **65' conceded**
4. **89' Tom Goodman goal**

The recovered event rows are marked `server_protected`.

Do not alter, delete or use Culdrose as a destructive test fixture unless the user explicitly asks.

The Culdrose voting event is already **open**. Do not create another one.

## The architectural problem still to review

`save_match_centre_state` still accepts the whole browser event array and deletes/reinserts event rows on save.

A guard now rejects stale payloads that omit protected server-corrected events, but the whole-array replacement model is still risky for a live Matchday app.

Review whether Matchday events should move to stable event-level create/edit/delete RPCs before the next real match.

## What to do first in this new chat

Do this in order:

1. Inspect current `main`, current `dev`, and the 26 September handover. Do not assume branches are aligned.
2. Inspect the **legacy Perranporth Matchday** implementation and make a parity checklist.
3. Inspect current Core `match-centre.html`, `save_match_centre_state`, `load_match_centre_state`, voting RPCs and current migrations.
4. Use a disposable/test fixture, not Culdrose, and run the whole match:
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
   - Full Time
   - correct final score/status
   - exact event reload
   - Live Score
   - voting auto-opens exactly once
   - player voting link opens correct team and correct saved-squad candidates
5. Check Supabase state after each critical transition.
6. Add smoke/integration protection for every regression.
7. Only then call Matchday ready.

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
