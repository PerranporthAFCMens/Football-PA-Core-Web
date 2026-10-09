# Supabase Schema Documentation (Stage 2)

**Last updated:** 9 Oct 2026  
**Status:** Stage 2 in progress — extracted from live Supabase project `hennzggqaquevqgiucqn`

This document describes the public schema for Football PA Core, extracted for Stage 2 database-in-repo implementation.

## Schema overview

The Football PA Core database consists of 37 tables in the `public` schema, organized into logical groups:

### Core (6 tables)
- **profiles** — User profile data (display_name, email, timestamps)
- **clubs** — Club/organization master data (name, slug, colors, active flag)
- **teams** — Teams within clubs (team_name, active status, settings references)
- **club_memberships** — User membership in clubs (role, permissions, active status)
- **team_memberships** — User membership in teams (role, permissions, access levels)
- **seasons** — Seasons within clubs (year, active status)

### Players & Squads (5 tables)
- **players** — Player master data (name, DOB, position, club reference)
- **team_players** — Player registration for teams (shirt number, role)
- **match_squads** — Squad lineup for a specific match (fixture reference)
- **match_lineups** — Starting lineup and bench (fixture, player, starter flag)
- **team_access_levels** — Custom access level definitions for granular permissions

### Fixtures & Matches (8 tables)
- **fixtures** — Match fixture records (date, teams, score, status)
- **match_events** — Events during match (goals, cards, substitutions)
- **substitutions** — Player substitution records (player_on, player_off, minute)
- **match_states** — Match state snapshots (clock, period, current_player)
- **subs_fixture_statuses** — Substitution status per fixture (confirmed, pending)
- **subs_settings** — Substitution template settings per team
- **subs_payments** — Payment/fine records for subs
- **fixture_availability_polls** — Availability polling for fixtures

### Voting (6 tables)
- **voting_templates** — Vote template definitions (club/team level)
- **voting_questions** — Questions within voting templates
- **voting_events** — Active voting events for a fixture
- **voting_ballots** — Individual voter ballots (one per voter per event)
- **voting_selections** — Individual question selections within ballots
- **fixture_availability_responses** — Responses to availability polls

### Training (2 tables)
- **training_sessions** — Training session records (team, date, time)
- **training_attendance** — Player attendance for training sessions

### Settings & Configuration (4 tables)
- **team_settings** — Per-team configuration (30 settings fields, extends core team data)
- **team_features** — Feature flags per team (player_portal, voting, etc.)
- **team_domains** — Custom domain mappings for teams
- **competitions** — Competition/league definitions

### Admin (4 tables)
- **platform_admins** — Platform-level administrators (active flag)
- **pending_team_access** — Pending invitations/access requests (email-based)
- **player_portal_credentials** — Legacy player portal login tokens
- **player_portal_sessions** — Legacy player portal session state

### Audit (2 tables)
- **player_season_snapshots** — Historical player snapshots per season
- **team_invite_links** — Invite link tracking (single-use, team invites via text)

## RLS policy matrix

All 37 tables have Row-Level Security (RLS) enabled. Policies follow a pattern:

| Scenario | Policy Type | Roles | Condition |
|----------|------------|-------|-----------|
| User reads own profile | SELECT | authenticated | `id = auth.uid()` |
| User reads own club members | SELECT | authenticated | user_id = auth.uid() |
| User reads own team members | SELECT | authenticated | user_id = auth.uid() |
| User reads club data | SELECT | authenticated | `can_access_club(club_id)` |
| User reads team data | SELECT | authenticated | `can_access_team(team_id)` |
| User reads fixture | SELECT | authenticated | `can_access_team(team_id)` |
| Manager manages team | INSERT/UPDATE | authenticated | `can_manage_team(team_id)` |
| Manager manages fixtures | INSERT/UPDATE | authenticated | `can_manage_fixtures(team_id)` |
| Manager manages players | INSERT/UPDATE | authenticated | `can_manage_players(team_id)` |
| Public reads active domains | SELECT | anon,authenticated | `active = true` |

Total RLS policies: **56** across the 37 tables.

## Key security functions (SECURITY DEFINER)

These functions enforce access control and are used by RLS policies:

| Function | Arguments | Returns | Purpose |
|----------|-----------|---------|---------|
| `can_access_club(club_id)` | uuid | boolean | Checks if user is club member or team member in club |
| `can_access_team(team_id)` | uuid | boolean | Checks if user is active team member |
| `can_access_fixture(fixture_id)` | uuid | boolean | Checks if user can access fixture's team |
| `can_access_player(player_id)` | uuid | boolean | Checks if user can view player (club or team) |
| `can_manage_team(team_id)` | uuid | boolean | Checks if user has management role in team |
| `can_manage_fixtures(team_id)` | uuid | boolean | Checks if user can edit fixtures |
| `can_manage_players(team_id)` | uuid | boolean | Checks if user can manage team players |
| `can_manage_voting(team_id)` | uuid | boolean | Checks if user can manage voting |
| `is_platform_admin()` | — | boolean | Checks if current user is active platform admin |
| `apply_pending_team_access()` | — | trigger | Trigger function: creates team memberships from pending invites on user signup |
| `calculate_player_fixture_minutes(fixture_id, player_id, match_minutes)` | uuid, uuid, int | integer | Calculates minutes played considering subs and red cards |

## Trigger functions

| Trigger | Event | Table | Function | Purpose |
|---------|-------|-------|----------|---------|
| `on_auth_user_created` | AFTER INSERT | auth.users | `apply_pending_team_access()` | Create team memberships for pending invites when user signs up |
| `on_profile_created` | AFTER INSERT | profiles | Auto-create entry in platform_admins if invited | Legacy: handled by trigger |
| Various `updated_at` triggers | BEFORE UPDATE | All tables | `moddatetime('updated_at')` | Auto-update `updated_at` timestamp |

## Constraints and relationships

### Foreign keys (inter-table)
- `profiles.id` → `auth.users.id` (external)
- `club_memberships.user_id` → `profiles.id`
- `club_memberships.club_id` → `clubs.id`
- `teams.club_id` → `clubs.id`
- `team_memberships.user_id` → `profiles.id`
- `team_memberships.team_id` → `teams.id`
- `team_memberships.player_id` → `team_players.id` (nullable)
- `team_memberships.access_level_id` → `team_access_levels.id` (nullable)
- `players.club_id` → `clubs.id`
- `team_players.team_id` → `teams.id`
- `team_players.player_id` → `players.id`
- `fixtures.home_team_id` → `teams.id`
- `fixtures.away_team_id` → `teams.id`
- `fixtures.season_id` → `seasons.id`
- `match_events.fixture_id` → `fixtures.id`
- `match_events.player_id` → `team_players.id` (nullable)
- `match_lineups.fixture_id` → `fixtures.id`
- `match_lineups.player_id` → `team_players.id`
- `match_squads.fixture_id` → `fixtures.id`
- `substitutions.fixture_id` → `fixtures.id`
- `substitutions.player_on_id` → `team_players.id`
- `substitutions.player_off_id` → `team_players.id` (nullable)
- `training_sessions.team_id` → `teams.id`
- `training_attendance.session_id` → `training_sessions.id`
- `training_attendance.player_id` → `team_players.id`
- `voting_templates.club_id` / `team_id` → `clubs.id` / `teams.id` (nullable pairing)
- And many others...

### Unique constraints
- `clubs.slug` — Organization slug must be unique
- `team_domains.domain` — Domain per organization (nullable)
- Various composite unique constraints on membership/player tables

### Indexes
- Primary keys on all tables
- Indexes on foreign key columns
- Indexes on `created_at`, `updated_at` for date-based queries
- Indexes on team_id, club_id for common access paths
- Indexes on user_id for membership lookups

## Multi-team/multi-club isolation

The RLS policies and `FootballPAContext` helper ensure users only see data for:
1. Clubs they are members of
2. Teams within those clubs
3. Fixtures, players, and match data for those teams only

No user can query across club boundaries unless they are a platform admin.

## Extensions and special types

The Supabase project uses:
- **uuid** type with `gen_random_uuid()` defaults
- **timestamptz** (timestamp with time zone) for all temporal data
- **jsonb** for flexible settings storage (team_settings table)
- **moddatetime** extension: provides the `moddatetime()` function for auto-updated_at

## Stage 2 files

Migration files for database rebuild:

| File | Purpose | Status |
|------|---------|--------|
| `20261009000000_baseline_schema.sql` | Create all tables, columns, constraints, indexes | Complete |
| `20261009010000_rls_policies.sql` | RLS policy definitions | Skeleton (56 policies to add) |
| `20261009020000_database_functions.sql` | Functions, triggers, stored procedures | Skeleton (11+ functions to add) |
| `20261009030000_role_grants.sql` | Role permissions (authenticated, anon, service_role) | Skeleton |

## Notes for Stage 2

1. **Function extraction:** The function definitions are in `/root/.claude/projects/*/tool-results/mcp-Supabase-execute_sql-*.txt`. Each function has a full `CREATE OR REPLACE FUNCTION` definition that must be extracted and added to the migrations.

2. **RLS policy recreation:** All 56 policies reference security functions. Functions must be created before policies to avoid dependency errors on rebuild.

3. **Triggers:** Supabase manages some triggers automatically (moddatetime). Others are in the functions file and must be created with `CREATE TRIGGER`.

4. **Service role keys:** Never expose service_role keys in frontend code. Used only for backend operations (Discord bot, edge functions).

5. **Vercel compatibility:** Edge functions for team invite links and other features use the Supabase client with a service_role key in a secure environment variable, never in the browser.

---

**Extracted from live Supabase project:** hennzggqaquevqgiucqn  
**Export date:** 9 October 2026  
**Next step (Stage 2):** Populate migration files with exact function and policy definitions, verify rebuild against live schema, test dummy match flow.
