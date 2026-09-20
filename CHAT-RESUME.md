# Resume Football PA Core in a new chat

Paste this into a new conversation:

---

We are continuing development of **Football PA Core**.

Repository: `PerranporthAFCMens/Football-PA-Core-Web`  
Supabase project: `hennzggqaquevqgiucqn`  
Primary site: `https://core.footballpa.com`

First read `README.md`, `HANDOVER.md`, `CODE-AUDIT.md` and `scripts/smoke-check.mjs` from the current `main` branch. Treat them as the current source of truth.

Rules:
- Perranporth is the UX reference. Core must stay generic/configurable.
- Do not modify the separate live Perranporth app unless explicitly asked.
- Inspect exact code/schema before editing.
- Do not claim a fix is done until it is pushed/applied and checked.
- Batch changes because Vercel has been hitting build-rate limits.
- GitHub main may be ahead of Vercel, so check deployment status separately.
- Use British English and avoid em dashes.

Current QA team: St Agnes Dynamos Girls U10  
Team ID: `5337936a-5db7-4447-ac4a-d50323eb0715`  
Season ID: `f8ef6074-d483-4dd1-b15c-1957305469d3`

The highest-priority known technical issue is match-lineup history. Normal Match Centre saves currently replace `match_lineups` with the current XI. Read the handover before changing that architecture.

Continue from current `main`, not from assumptions based on an older deployed page.

---
