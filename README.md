# Football PA Core

Multi-team football/soccer management platform for organizing matches, tracking squad data, and managing player lineups.

**Live:** https://footballpa.com | **Dev:** https://dev.footballpa.com

---

## Architecture

Football PA Core uses a **HybridOne-style architecture** with clear development and production separation:

| Aspect | Dev | Production |
|--------|-----|------------|
| **Branch** | `dev` | `main` |
| **URL** | dev.footballpa.com | footballpa.com |
| **Host** | GitHub Pages (auto) | Vercel (manual) |
| **Deploy** | Auto on every push | Manual release workflow only |
| **Purpose** | Testing, features | Live data, live teams |

### Key Principle

- Push to `dev` → auto-deploys within 1-2 minutes to dev.footballpa.com
- Push to `main` → requires **manual release approval** before deploying to footballpa.com
- Single repository; clear branch responsibility
- Rollback tags (prod-YYYY-MM-DD) for emergency recovery

---

## Tech Stack

- **Frontend:** HTML5, CSS3, vanilla JavaScript (no framework)
- **Database:** Supabase (PostgreSQL, Row-Level Security, Edge Functions)
- **Auth:** Supabase Auth + JWT
- **Email:** Resend
- **Hosting:** Vercel (production), GitHub Pages (development)
- **Infrastructure:** Single Supabase project with schemas for dev/prod

---

## Development Workflow

### 1. Set Up Locally

```bash
git clone https://github.com/PerranporthAFCMens/Football-PA-Core-Web.git
cd Football-PA-Core-Web
```

### 2. Create a Feature Branch

```bash
git checkout dev
git pull origin dev
git checkout -b feat/your-feature-name
```

### 3. Make Changes & Test on Dev

```bash
# Edit files locally or push to GitHub
git push origin feat/your-feature-name

# Test live on dev.footballpa.com (auto-deploys within 1-2 min)
# Make sure everything works before requesting merge
```

### 4. Merge to Dev

Create a PR: `feat/your-feature-name` → `dev`
- Requires 1 approval (set up via GitHub rulesets)
- Smoke checks must pass
- Merge and delete branch

### 5. Release to Production

See [RELEASE.md](./RELEASE.md) for full instructions. Quick version:

```bash
# 1. Test everything on dev.footballpa.com (URL: dev.footballpa.com?team=<id>)
# 2. Get dev branch's latest commit SHA
git rev-parse origin/dev

# 3. Go to GitHub Actions → Manual Production Release workflow
# 4. Run workflow with that SHA
# 5. Deploy to Vercel when workflow completes
# 6. Verify footballpa.com works
```

---

## Branches

| Branch | Purpose | Auto-Deploy |
|--------|---------|-------------|
| `dev` | Development; test features here | Yes → dev.footballpa.com |
| `main` | Production release branch | No (manual gate) |
| `feat/*` | Feature work; branch from `dev` | No |
| `fix/*` | Bug fixes; branch from `dev` | No |
| `release/*` | Release staging (created by workflow) | No |

### Branch Rules (GitHub Rulesets)

**Dev Branch:**
- Require 1 PR review before merge
- Require status checks (smoke tests)
- Dismiss stale reviews on push
- Enforce up-to-date before merge

**Main Branch:**
- Require 1 PR review before merge
- Require status checks
- Require PRs only from `dev` branch
- Admins can bypass (emergency fixes only)

---

## Database & Migrations

**Supabase Project:** Football PA Core (`hennzggqaquevqgiucqn`)

### Structure

- **Schema:** Public tables + RLS for multi-team isolation
- **Migrations:** `supabase/migrations/` (version controlled)
- **Edge Functions:** `supabase/functions/` (Deno, version controlled)
- **Auth:** Supabase Auth (JWT)

### Adding a Migration

```bash
# Create locally (if using Supabase CLI)
supabase migration new <name>

# Or add directly to supabase/migrations/
# File format: YYYYMMDDHHMMSS_description.sql

# Apply to remote
supabase migration up --linked
```

---

## Teams Using Football PA

- **Perranporth AFC** - First team, live data, match stats
- **Dynamos Girls U10** - Trial phase (coach testing)
- **Harbour Athletic FC** - Demo/test team

### Adding a New Team

Use the Player Portal or Admin interface (TBD: add URL)

---

## Common Tasks

### Test Match Centre

1. Go to dev.footballpa.com?team=perranporth
2. Open a fixture (or create test fixture)
3. Click "Match Centre"
4. Test clock, events, lineup, substitutions
5. Verify saves are working (check browser console for errors)

### Run a Live Match

1. Verify on dev first
2. Test Player Portal (if live)
3. Monitor Match Centre during match
4. Check for any "NOT SAVED" warnings
5. Post-match: verify final stats and lineup recorded

### Rollback Production

If production breaks:

1. Identify the issue (check Vercel logs)
2. Note the rollback tag (e.g., `prod-2026-10-08`)
3. Open Vercel dashboard
4. Go to Deployments → find previous good deployment
5. Click "Instant Rollback"
6. Verify footballpa.com is restored

---

## Monitoring

### Dev Deploys

- Check GitHub Actions tab; GitHub Pages runs on every push to `dev`
- Visit dev.footballpa.com to verify
- If Pages build fails: check GitHub repo Settings → Pages

### Production Deploys

- Check Vercel dashboard: PerranporthAFCMens → football-pa-core-web
- Monitor footballpa.com for errors
- Perranporth team: confirm they can access their data

### Database

- Supabase dashboard: https://supabase.com/dashboard
- Check logs for Edge Function errors
- Monitor RLS policies if multi-team access issues occur

---

## Troubleshooting

**Dev site not updating?**
- Check GitHub Pages build status (repo Settings → Pages)
- Verify `dev` branch has the latest code
- Wait 2-3 minutes; Pages can be slow

**Production deploy stuck?**
- Check Vercel build logs
- Verify all environment variables are set
- Check Supabase is online

**Teams can't access data?**
- Verify RLS policies in Supabase
- Check team IDs match in database
- Confirm user is authenticated

---

## Support & Questions

- **Current status:** See STATUS.md
- **Known issues:** See STATUS.md
- **Release process details:** See RELEASE.md
- **Database schema:** See Supabase dashboard

---

## Release History

| Date | Release | Notes |
|------|---------|-------|
| 3 Oct 2026 | Save fix | Match Centre now marks unsaved changes |
| 2 Oct 2026 | Release gate | Manual production deployments |
| 4 Oct 2026 | Invite by text | SMS/WhatsApp team invite links |
| 8 Oct 2026 | Architecture | HybridOne-style dev/prod separation |

---

Generated with Claude Code  
https://claude.ai/code/session_01UoBqykv9hKzcu2nEceQRW3
