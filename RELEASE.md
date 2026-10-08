# Production Release Process

Football PA Core uses a **manual release gate** to keep production stable. This document walks through the controlled release workflow.

---

## Before You Release

### Checklist

- [ ] All features tested on dev.footballpa.com (at least 5 minutes)
- [ ] No critical bugs or errors in Match Centre
- [ ] Database migrations applied and tested
- [ ] Edge Functions deployed and working
- [ ] Teams (Perranporth, Dynamos) have confirmed no blocking issues
- [ ] Vercel environment variables are up to date
- [ ] Supabase is healthy (check dashboard)

### Communication

If releasing during match season:
- [ ] Notify Perranporth team that deploy is happening
- [ ] Schedule for off-hours if possible (after match day)
- [ ] Have a rollback plan ready

---

## Release Workflow

### Step 1: Prepare on Dev (10 min)

Make sure all changes are on `dev` and tested live:

```bash
git checkout dev
git pull origin dev

# Verify latest changes are live at dev.footballpa.com
# Test the specific features being released
```

**Test on:** https://dev.footballpa.com?team=perranporth

### Step 2: Get the Release Commit SHA (2 min)

```bash
git rev-parse origin/dev
# Example output: a94d3173bfdd544d5f8ebca6ee88bc1d2ae48d97
```

Copy this SHA. You'll need it for the workflow.

### Step 3: Run Release Workflow (5 min)

1. Open GitHub repo: https://github.com/PerranporthAFCMens/Football-PA-Core-Web
2. Click **Actions** tab (top)
3. Select **Manual Production Release** workflow (left sidebar)
4. Click **Run workflow** (blue button, right side)
5. Paste the dev SHA in **dev_sha** field
6. Leave **rehearsal** unchecked (to actually deploy)
7. Click **Run workflow**

**The workflow will:**
- Verify the commit is on dev branch
- Run smoke checks
- Create a release candidate
- Provide deployment instructions

### Step 4: Deploy via Vercel (5 min)

Once workflow completes:

1. Open Vercel: https://vercel.com/dashboard
2. Select football-pa-core-web project
3. Click **Deployments** (left sidebar)
4. Create a new deployment:
   - **Branch:** `main`
   - Trigger deployment manually
5. Wait for build to complete (usually 2-3 min)
6. Confirm deployment is **Ready**

### Step 5: Verify Production (5 min)

Open https://footballpa.com and test:

- [ ] Page loads without errors
- [ ] Logo and branding appear correct
- [ ] Team switcher works (if logged in)
- [ ] Match Centre opens and responds
- [ ] Player Portal loads (if enabled)
- [ ] Test team (Perranporth): data is visible
- [ ] Check browser console for any errors

### Step 6: Notify Teams (2 min)

Message Perranporth and Dynamos coaches:
> ✓ Production deployed. footballpa.com is updated to latest version. No action needed.

---

## If Something Goes Wrong

### Issue During Deploy

If the Vercel build fails:

1. Check Vercel logs for the error
2. Fix the issue on `dev` branch
3. Repeat from Step 2 with a new commit SHA

### Issue After Deploy

If production is broken after deploy:

#### Quick Rollback (2 min)

1. Open Vercel dashboard
2. Go to **Deployments**
3. Find the previous good deployment (usually the one before the latest)
4. Click it, then click **Instant Rollback**
5. Confirm
6. Verify footballpa.com works

#### Rollback Tag

The workflow output provides a rollback tag (e.g., `prod-2026-10-08`). Use this in Vercel's search to find the exact previous build:

1. Vercel dashboard → Deployments
2. Search for tag: `prod-2026-10-08`
3. Click that deployment
4. Use Instant Rollback

#### After Rollback

1. Investigate the bug
2. Fix on `dev` branch
3. Test thoroughly
4. Re-release with a new commit SHA

---

## Release Rehearsal (Optional)

To validate a release without deploying:

1. Follow **Step 3** (Run Release Workflow)
2. Check **rehearsal** checkbox
3. Click **Run workflow**
4. Workflow validates but does NOT deploy
5. Review the summary
6. When ready, repeat without rehearsal checked

**Use rehearsal for:**
- Validating a release candidate before full deploy
- Testing the workflow process
- Dry runs on complex releases

---

## GitHub Actions Workflow Details

The workflow file (`.github/workflows/manual-release.yml`) does:

1. **Validate** - Confirms commit is on dev branch
2. **Smoke checks** - Looks for obvious errors
3. **Release** (if not rehearsal) - Prepares deployment info
4. **Output** - Prints deployment summary with rollback tag

**Workflow Status:** Check GitHub Actions tab → Manual Production Release → latest run

---

## Vercel Environment Setup

### Build Settings

- **Framework:** None (static site)
- **Build command:** (empty; no build needed)
- **Output directory:** (empty; serves root)

### Environment Variables

Verify in Vercel → Settings → Environment Variables:

- `SUPABASE_URL` - Set to Supabase project URL
- `SUPABASE_ANON_KEY` - Public API key
- Any other secrets needed

**Note:** These should match dev and prod (or have prod-specific overrides)

---

## Deployment Domains

**Production:** footballpa.com (www.footballpa.com redirects here)

**Old domains (retired):**
- app.footballpa.com → redirects to footballpa.com
- core.footballpa.com → redirects to footballpa.com

---

## Monitoring After Release

### First 5 Minutes

- Refresh footballpa.com multiple times
- Check browser console for errors
- Try Match Centre (open a fixture)
- Test team switcher

### First Hour

- Perranporth team: check they can access data
- Verify no Supabase errors (check Supabase dashboard)
- Check Vercel logs for any warnings

### Daily

- Monitor Vercel deployment health (dashboard shows uptime)
- Check Supabase for slow queries or Edge Function errors

---

## Release Schedule

**Recommended:**
- **Weekdays (off-season):** Any time, no restrictions
- **During match season:** After match day (not Saturday evening/Sunday morning)
- **Emergency rollback:** Anytime

---

## Questions?

See README.md for general setup and development.
See STATUS.md for current project status and known issues.

Last updated: 8 Oct 2026
