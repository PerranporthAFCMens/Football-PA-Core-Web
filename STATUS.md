# Football PA Core: STATUS

Read this file and AI_WORKING_RULES.md at the start of every session. Anything not written here counts as forgotten.

## Where we are (2 Oct 2026)

- Work is now done with Claude only. ChatGPT has stopped working on Football PA.
- Production is `main` at `5f475da` ("Guard legacy-style lineup drag ghost", 28 Sep). `dev` is identical.
- Live addresses (Vercel project `football-pa-core-web`): footballpa.com, app.footballpa.com, core.footballpa.com. Vercel deploys every change to `main`.
- Database: Supabase project "Football PA Core" (`hennzggqaquevqgiucqn`). It also holds the old Perranporth app data (`perranporth` schema) and QuarryHQ tables.

## Teams using the app and the freeze

- Perranporth 1st Team: Saturdays (next: Falmouth United away, Sat 10 Oct, 2:30pm).
- Dynamos Girls U10: Sundays (next: Elevate Pencoys away, Sun 4 Oct).
- No releases and no live database changes from Friday 18:00 to Sunday 23:59 UK time.

## Live changes log (with rollback)

| Date | Change | Who | Rollback |
|---|---|---|---|
| 2 Oct 2026 | Disabled "Hourly production release" workflow (Football-PA-Core-Web) | Adam | Re-enable in Actions tab |
| 2 Oct 2026 | Disabled "Sync Perranporth app" workflow (Football-PA website repo) | Adam | Re-enable in Actions tab |

## Culdrose (26 Sep) findings

- Match Centre then saved the whole match every few seconds, deleting and re-inserting all events and subs.
- Two changes were applied to the live database during the first half (14:54 clock, 15:13 event protection). The 15:13 change rejected every later save from the open Match Centre, so nothing saved from 15:13 until after the match. It also reverted the 14:54 clock change.
- On 27 Sep Match Centre was rebuilt to save each event individually (`upsert_match_event`). The old whole-match function `save_match_centre_state` still exists in the database but the current app no longer calls it.

## Known risks

1. A failed goal/card/sub save shows as saved, then disappears about 5 seconds later with no warning. Fix before Falmouth.
2. The only automated check (`Core smoke checks`) searches source files for text. It does not test real behaviour. Until the browser test exists, the release requires a manual dummy match on the dev preview.
3. Database changes are not yet in the repo (Stage 2).
4. A "MATCHDAY TEST - DELETE" fixture sits in Perranporth's live data.
5. The old Perranporth copy on the Football PA website is frozen at `5f475da` and its sync workflow is disabled. It uses the same live database, so it must not be used to run a match. Adam prefers its layout; bring that layout into Football PA after stabilisation.

## Plan

- Stage 1: release gate (PR #16), GitHub rulesets on `main` and `dev`.
- Fix: failed-save warning and retry in Match Centre. Dummy match on Thu 8 Oct.
- After Falmouth: Stage 2 database in repo, Stage 3 Match Centre browser test, Stage 4 refactor (clock/events state machine).

## How to release

1. Run a dummy match on the dev preview with the current dev version.
2. Actions → "Manual production release" → Run workflow → paste the dev SHA → tick the rehearsal box.
3. If the live site misbehaves: Vercel → football-pa-core-web → Deployments → previous production deployment → Instant Rollback.
