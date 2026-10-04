# Football PA Core: STATUS

Read this file and AI_WORKING_RULES.md at the start of every session. Anything not written here counts as forgotten.

## Where we are (3 Oct 2026)

- Work is now done with Claude only. ChatGPT has stopped working on Football PA.
- Release gate live on `main` (PR #16, merged 2 Oct). `dev` brought level with `main` (PR #18).
- Save fix (`match-save-guard.js`, PR #17) released to production 3 Oct (rollback tag `prod-2026-10-03`).
- In progress: invite staff by text/WhatsApp (shareable single-use link, `join.html`, `team_invite_links` table, `team-invite-link-signup` edge function).
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

- Stage 1: release gate (PR #16, done), GitHub rulesets on `main` and `dev` (to do).
- Fix: failed-save warning and retry in Match Centre (PR #17, released).
- Dynamos handover: delete five demo fixtures and record Falmouth 20 Sep result (SQL awaiting approval); invite-by-text for coaches (this PR).
- Stage 2 database in repo, Stage 3 Match Centre browser test, Stage 4 refactor (clock/events state machine).

## How to release

1. Run a dummy match on the dev preview with the current dev version.
2. Actions → "Manual production release" → Run workflow → paste the dev SHA → tick the rehearsal box.
3. If the live site misbehaves: Vercel → football-pa-core-web → Deployments → previous production deployment → Instant Rollback.
