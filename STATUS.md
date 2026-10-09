# Football PA Core: STATUS

Read this file and AI_WORKING_RULES.md at the start of every session. Anything not written here counts as forgotten.

## Where we are (6 Oct 2026)

- Work is now done with Claude only. ChatGPT has stopped working on Football PA.
- Release gate live on `main` (PR #16, merged 2 Oct). `dev` brought level with `main` (PR #18).
- Save fix (`match-save-guard.js`, PR #17) released to production 3 Oct (rollback tag `prod-2026-10-03`).
- Invite staff by text/WhatsApp: shareable single-use link. Database table/functions and edge function are live; `join.html` and the Access Management button shipped in PR `feat/invite-link-by-text`.
- **In progress**: lineup confirmation workflow (two-phase: "Confirm starting lineup" pre-match, "Edit starting lineup" during match with warning). Edge function `confirm-starting-lineup` created, Match Centre UI updated (PR `feat/lineup-confirmation`).
- Live addresses (Vercel project `football-pa-core-web`): footballpa.com, app.footballpa.com, core.footballpa.com. Vercel deploys every change to `main`.
- Database: Supabase project "Football PA Core" (`hennzggqaquevqgiucqn`). It also holds the old Perranporth app data (`perranporth` schema) and QuarryHQ tables.

## Teams using the app

- Perranporth 1st Team: Saturdays (next: Falmouth United away, Sat 10 Oct, 2:30pm).
- Dynamos Girls U10: not using the app yet. Adam is trialling it before handing it to the coaches. Player Portal stays off. Kick-off times are confirmed week by week and edited on the Fixtures page. Palm Beach is a demo fixture kept for final testing.
- Harbour Athletic FC: demo club. Use its Coastline Athletic fixture for testing.
- No matchday freeze (removed 2 Oct at Adam's request). If something breaks mid-match, roll back in Vercel.

## Live changes log (with rollback)

| Date | Change | Who | Rollback |
|---|---|---|---|
| 2 Oct 2026 | Disabled "Hourly production release" workflow (Football-PA-Core-Web) | Adam | Re-enable in Actions tab |
| 2 Oct 2026 | Disabled "Sync Perranporth app" workflow (Football-PA website repo) | Adam | Re-enable in Actions tab |
| 2 Oct 2026 | Release gate merged to `main` (PR #16); Vercel redeployed, app unchanged | Adam | Vercel Instant Rollback |
| 3 Oct 2026 | First release via Release button: save fix live | Adam | Tag `prod-2026-10-03` / Vercel Instant Rollback |
| 4 Oct 2026 | Migration `team_invite_links` applied (new table + 4 functions, additive) | Claude, approved by Adam | Drop the table and the four `*team_invite_link*` functions |
| 4 Oct 2026 | Edge function `team-invite-link-signup` deployed (verify_jwt off; the invite token is the check) | Claude, approved by Adam | Delete the function in Supabase |
| 4 Oct 2026 | Dynamos: deleted 5 demo fixtures (Demo United, Test Town, Sample City, Trial Athletic, Practice Rovers) and their events/subs; Falmouth 20 Sep set to completed, 1-10 | Claude, approved by Adam | None for the deletes (demo data); Falmouth score editable on Fixtures page |
| 9 Oct 2026 | Stage 2 database extraction: baseline_schema.sql created (37 tables, 240+ columns); RLS/functions/grants migration skeletons; SUPABASE_SCHEMA.md documentation | Claude | None yet (migrations are skeletons, pending function extraction) |

## Culdrose (26 Sep) findings

- Match Centre then saved the whole match every few seconds, deleting and re-inserting all events and subs.
- Two changes were applied to the live database during the first half (14:54 clock, 15:13 event protection). The 15:13 change rejected every later save from the open Match Centre, so nothing saved from 15:13 until after the match. It also reverted the 14:54 clock change.
- On 27 Sep Match Centre was rebuilt to save each event individually (`upsert_match_event`). The old whole-match function `save_match_centre_state` still exists in the database but the current app no longer calls it.

## Known risks

1. Fixed and released (PR #17): failed saves now stay on screen marked NOT SAVED, with a banner and automatic retry.
2. The only automated check (`Core smoke checks`) searches source files for text. It does not test real behaviour. Until the browser test exists, the release requires a manual dummy match on the dev preview.
3. Database changes are not yet in the repo (Stage 2). New changes now go in `supabase/migrations/` and `supabase/functions/`.
4. A "MATCHDAY TEST - DELETE" fixture sits in Perranporth's live data.
5. The old Perranporth copy on the Football PA website is frozen at `5f475da` and its sync workflow is disabled. It uses the same live database, so it must not be used to run a match. Adam prefers its layout; bring that layout into Football PA after stabilisation.

## Plan

- Stage 1: release gate (PR #16, done), GitHub branch protection on `main` and `dev` (PR #22, in review).
- Fix: failed-save warning and retry in Match Centre (PR #17, released).
- Dynamos handover: demo fixtures deleted and Falmouth result recorded (done 4 Oct); invite-by-text for coaches (PR #19, live).
- Multi-team users have no team switcher in the menu; they switch with `index.html?team=<id>`. Candidate improvement.
- **Stage 2 database in repo** (in progress): baseline schema extracted, RLS/functions/roles migration skeletons created, SUPABASE_SCHEMA.md documentation written. Next: populate function and policy definitions, rebuild test, PR #23.
- Stage 3 Match Centre browser test, Stage 4 refactor (clock/events state machine).

## How to release

1. Run a dummy match on the dev preview with the current dev version.
2. Actions → "Manual production release" → Run workflow → paste the dev SHA → tick the rehearsal box.
3. If the live site misbehaves: Vercel → football-pa-core-web → Deployments → previous production deployment → Instant Rollback.
