# Perranporth → Football PA Core migration

Date: 21 September 2026

## Goal

Move Perranporth onto the shared Football PA Core platform without turning Core into a Perranporth-specific fork and without changing the public player-portal URL players already use.

## Imported

### 2026/27
- club/team configuration and branding
- current squad and player portal credentials
- fixtures and grounds
- starter/squad records where available
- goals, conceded goals and substitutions
- 3–2–1 + Dick of the Day vote history
- subs configuration and legacy paid/claimed-paid records

### 2025/26
- completed fixtures and score reconstruction from the historic event workbook
- goal/conceded and substitution event history
- player season snapshots for appearances, minutes, goals and assists

## Access compatibility

Core supports both:
- normal Supabase-authenticated player accounts
- team-scoped legacy PIN player access

PIN access uses hashed credentials and opaque hashed session tokens. Direct browser access to credential/session tables is blocked by RLS and grants.

Legacy management users who do not yet have Supabase accounts are held as pending team access. When they create an account with the matching email address, the database grants the configured Perranporth team membership.

## Statistics

Fixtures have an `include_in_stats` flag. Perranporth's old `Include` value maps to this flag so pre-season/test fixtures can remain visible without changing performance statistics.

## Cut-over

1. Verify Perranporth in Dev Admin → View as team.
2. Verify Player Portal using team-scoped PIN mode.
3. Promote the single Core migration commit to production.
4. Verify production.
5. Only then update the old Perranporth `player.html` compatibility page so its URL remains unchanged.
