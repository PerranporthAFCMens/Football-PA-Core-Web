# Football PA Core Web

Football PA Core is the generic, multi-club web application behind Football PA. The Perranporth app is the UX reference, but Core must remain team-agnostic and configurable.

## Production shape

- Front end: static HTML/CSS/JavaScript on Vercel
- Repository: `PerranporthAFCMens/Football-PA-Core-Web`
- Primary domain: `https://core.footballpa.com`
- Data/auth: Supabase project `hennzggqaquevqgiucqn`
- Shared shell: `core-context.js`, `core-nav.js`, `core-ui.css`

## Main routes

- `/` Home
- `/fixtures.html` Fixtures
- `/match-centre.html` Match Centre
- `/dashboard.html` Team and player performance
- `/players.html` Player management and training log
- `/voting.html` Voting
- `/subs.html` Subs / finance
- `/team-settings.html` Team settings

The old `/training.html` route is retained only for backwards compatibility.

## Product rule

Build once, configure per club/team. Do not introduce team-specific branches or deployments into Core. When a UX decision already exists in Perranporth, inspect the Perranporth implementation before inventing a new pattern.

## Checks

Run:

```bash
node scripts/smoke-check.mjs
```

For active project state and deployment caveats, read [HANDOVER.md](HANDOVER.md). For a ready-to-paste prompt for a new ChatGPT conversation, read [CHAT-RESUME.md](CHAT-RESUME.md).
