# Branch Protection Rules

## Setup Instructions

Branch protection rules for `dev` and `main` have been configured via GitHub API to enforce development workflow discipline.

### Dev Branch

Required protections:
- **1 required review**: Pull requests must have at least 1 approval before merging
- **Status checks required**: Merges blocked until required checks pass
- **Dismiss stale reviews**: New commits automatically dismiss previous reviews

Apply with:
```bash
gh api repos/PerranporthAFCMens/Football-PA-Core-Web/branches/dev/protection \
  --method PUT \
  -f required_status_checks.strict=true \
  -f required_status_checks.contexts=[] \
  -f enforce_admins=false \
  -f require_code_owner_reviews=false \
  -f required_approving_review_count=1 \
  -f dismiss_stale_reviews=true \
  -f restrictions=null
```

### Main Branch

Required protections:
- **1 required review**: Pull requests must have at least 1 approval before merging
- **Status checks required**: Merges blocked until required checks pass
- **Dismiss stale reviews**: New commits automatically dismiss previous reviews
- Enforced via the Manual production release workflow (no direct pushes)

Apply with:
```bash
gh api repos/PerranporthAFCMens/Football-PA-Core-Web/branches/main/protection \
  --method PUT \
  -f required_status_checks.strict=true \
  -f required_status_checks.contexts=[] \
  -f enforce_admins=false \
  -f require_code_owner_reviews=false \
  -f required_approving_review_count=1 \
  -f dismiss_stale_reviews=true \
  -f restrictions=null
```

## How They Work

- **Dev branch**: Requires reviews on all PRs. Protects against accidental direct commits to dev.
- **Main branch**: Requires reviews. Manual production release workflow controls promotion from dev to main. No automatic promotions.
- **Status checks**: Both branches require GitHub Actions checks to pass before merge. Currently: Core smoke checks (text-based validation). Browser tests will be added in Stage 3.
- **Stale review dismissal**: Ensures reviews are fresh when new commits are pushed. Reviewers must re-approve after code changes.

## Verification

After running the commands, verify the rules are active:

```bash
gh api repos/PerranporthAFCMens/Football-PA-Core-Web/branches/dev --jq '.protection'
gh api repos/PerranporthAFCMens/Football-PA-Core-Web/branches/main --jq '.protection'
```

Both should show `"enabled": true` with the above settings.

## Related Files

- `AI_WORKING_RULES.md` - Development workflow rules (one branch per task, PR reviews, etc.)
- `STATUS.md` - Project status and release procedures
- `.github/workflows/manual-release.yml` - Manual production release workflow
