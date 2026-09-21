# Resume Football PA Core in a new chat

Paste this into a new conversation:

---

We are continuing development of **Football PA Core**.

Repository: `PerranporthAFCMens/Football-PA-Core-Web`  
Supabase project: `hennzggqaquevqgiucqn`  
Primary site: `https://core.footballpa.com`

Before changing anything, read these files from the current `main` branch:
- `README.md`
- `HANDOVER.md`
- `CODE-AUDIT.md`
- `CHAT-RESUME.md`
- `scripts/smoke-check.mjs`

Treat those files as the current source of truth.

Important product rules:
- Perranporth is the UX reference, but Core must stay generic and configurable for any club/team.
- Do not modify the separate live Perranporth app unless I explicitly ask.
- Inspect exact code/schema before editing. Do not guess.
- Do not say a fix is complete until it is actually pushed/applied and checked.
- Check GitHub deployment status separately from code state because Vercel has previously hit build-rate limits.
- Use British English and avoid em dashes.

Current QA team:
- St Agnes Dynamos Girls U10
- team ID: `5337936a-5db7-4447-ac4a-d50323eb0715`
- season ID: `f8ef6074-d483-4dd1-b15c-1957305469d3`
- 7-a-side
- four x 12 minute periods

Current main navigation:
Home → Fixtures → Match Centre → Live Score → Dashboard → Players & Training → Voting → Subs Admin → Settings.

Recent completed work you need to preserve:
- Players & Training is admin/tools only, not a player performance dashboard.
- Players defaults to surname A–Z and can sort by surname, shirt number or first name.
- Training sessions can be Save & locked, then explicitly unlocked for corrections.
- Live Score is a spectator-safe tokenised public page using the `team-scoreboard` Edge Function. It refreshes from Match Centre and has a Share button.
- Match Centre uses one period button that changes Start/End state for each configured period.
- Saved starting lineup is reversible with **Edit starting lineup**.
- Goal logging uses the approved 10-zone half-pitch map.
- `match_events.zone` is integer. The Supabase save RPC was fixed to convert incoming values like `Zone 1` into numeric zone `1`.
- Dashboard mobile overflow has been fixed.
- Dashboard Player data scrolls horizontally inside its card. The Player column stays sticky and displays first name + surname initial, for example `Olivia T.`.

The Match Centre persistence architecture was fixed on 21 September 2026:
- `match_states.current_xi` stores the current tactical XI
- routine `save_match_centre_state` no longer rewrites `match_lineups`
- explicit starting-lineup confirmation/correction uses `set_match_starting_lineup`
- `load_match_centre_state` returns current `xi` separately from `starting_xi`
- substitution rows are rebuilt into the visible event feed after reload

The next known architectural review area is fixture/front-end permission alignment where UI `canManage` and database RLS may not always describe the same manager/admin roles.

Continue from the current `main` branch. Do not infer state from an older Vercel page without checking the current commit/deployment.

---