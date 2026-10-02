# AI Working Rules (Football PA Core)

Adapted from the HybridOne rules. These apply to every task, every time.

## 1. How to work

1. **One task per branch.** Branch from `dev`, named `fix/...` or `feat/...`. Never push directly to `dev` or `main`.
2. **Open a pull request for every change.** The description lists what changed and why, every file touched, and anything noticed but not changed.
3. **Small changes.** More than roughly 5 files means stop and propose a plan first.
4. **Read before you edit.** Open the actual current file. Never work from memory.
5. **Do not touch unrelated code.** Log it as a suggestion instead.
6. **You open PRs. The owner merges. You never merge.**
7. **Nothing touches `main`, workflows, rulesets or the live Supabase project without the owner approving the exact text** (exact SQL, exact command, exact file change).
8. **Stop at the first problem and report.** Do not fix forward. If something breaks after a release or live change, roll back first and investigate second.
9. **Update `STATUS.md` in every PR.** Read `STATUS.md` and this file at the start of every session and summarise where we are before doing anything.
10. **Say which team a change affects.** Perranporth 1st Team and Dynamos Girls U10 are real teams using the app.
11. **Plain English.** The owner is not a developer. Explain what each step does and what a pass or fail looks like.

## 2. Matchday freeze

- No releases, no live database changes and no feature work from **Friday 18:00 to Sunday 23:59 UK time**, or on any day a team using the app has a match.
- If something breaks on a matchday, the only allowed action is a rollback (Vercel Instant Rollback to the last good deployment). Investigate afterwards.

## 3. Definition of done

A change is not done until you have shown:

- the test command and its full output (pass/fail counts, not "looks good"),
- for any Match Centre change, a dummy match on the dev preview by the owner: start, goal for, goal against, sub, card, half-time, second half, full time, then reload the page and check everything is still there,
- confirmation that existing checks still pass.

"Fixed" without evidence means not fixed.

## 4. Database rules

- Every schema change is a migration file in the repo, reviewed in a PR. Never change the database only through the dashboard or an ad-hoc SQL call.
- Live Supabase is read-only unless the owner approves the exact SQL, outside the matchday freeze.
- Never remove or loosen an RLS policy to make a feature work.
- No service-role keys in frontend code, chat, SQL or the repo.
- Every live change is recorded in `STATUS.md` with its rollback.

## 5. Multi-team rules

- The active team always comes from `FootballPAContext`. Never pick one with `.limit(1)`, "first membership found" or a default ID.
- Changes to team selection are tested with an account that belongs to two teams with different roles.

## 6. Release rules

- `dev` reaches `main` only through the "Manual production release" workflow, after the required checks pass on the exact commit and the dummy match has been run.
- Each release tags the previous production commit `prod-YYYY-MM-DD` for rollback.
- No automatic promotion of any kind. The hourly promotion and the Perranporth 5-minute sync stay disabled.

## 7. Honesty rules

- Say when you are unsure, when a test is missing, or when a request conflicts with these rules.
- Report bugs outside the task. Do not silently fix them.
- If a request would break these rules, say so instead of complying.
