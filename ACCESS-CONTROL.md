# Football PA Core Access Control

Updated: 21 September 2026

This document defines the authoritative access model for Football PA Core.

## Principle

Access is resolved from one capability contract rather than each page independently interpreting roles.

The database is authoritative. Frontend code consumes `get_team_access_context(team_id)` and must not invent a separate role matrix.

## Roles

### Platform admin

Platform admins can access and manage all Core teams.

### Club owner / club admin

Club owners and club admins can access and manage every team in their club.

### Team admin / manager

Team admins and managers receive the standard team-management capabilities:

- match
- players
- fixtures
- settings
- voting
- subs

### Coach

Coaches receive:

- match
- players
- fixtures
- settings
- voting

Subs access is not automatic for a coach. It can be delegated explicitly.

### Treasurer

Treasurers receive Subs management access.

### Member / player

Members and players have read access to their team context. Management capability is only granted where an explicit permission has been delegated.

## Explicit permissions

Membership permission arrays can delegate a specific capability without changing a person's role.

Supported capability names are:

- match
- players
- fixtures
- settings
- voting
- subs

`subs_admin` is treated as the Subs capability. `admin` grants all capabilities.

Club-level delegated permissions apply to teams within that club.

## Core database helpers

The shared database contract is implemented through:

- `is_platform_admin()`
- `can_access_club(club_id)`
- `can_manage_club(club_id)`
- `can_access_team(team_id)`
- `team_has_capability(team_id, capability)`
- `can_manage_team(team_id)`
- `can_manage_match(fixture_id)`
- `can_manage_players(team_id)`
- `can_manage_fixtures(team_id)`
- `can_manage_voting(team_id)`
- `can_manage_subs(team_id)`
- `can_access_fixture(fixture_id)`
- `can_access_player(player_id)`
- `get_team_access_context(team_id)`

These helpers are available to authenticated users only. Anonymous Player Portal RPCs remain a separate public-session boundary.

## Frontend contract

`core-context.js` loads `get_team_access_context` and exposes it as both `ctx.access` and `ctx.capabilities`.

Existing `ctx.canManage` remains for compatibility and maps to `can_manage_team`.

Management surfaces use their own capability:

- Match Centre: `can_manage_match`
- Players / Training: `can_manage_players`
- Fixtures / Fixture Sync: `can_manage_fixtures`
- Voting Centre: `can_manage_voting`
- Subs Tracker: `can_manage_subs`
- Team Settings: `can_manage_team`

## RLS rules

A team-only member can now resolve the club and season required to render Core.

A team member can read players linked to their team. A user with Players management capability can read the wider club player pool so existing players can be reused without creating duplicates.

Club owners/admins and platform admins receive the same team access through RLS that the frontend advertises.

Fixture writes, team settings, team features, training writes and player-management writes use the matching capability helper.

## Regression tests completed

The Recommendation 1 audit tested the database using simulated authenticated JWT contexts inside rolled-back transactions.

Verified:

- an existing team-only Perranporth manager resolves the club, seasons, full player pool, roster, fixtures, team settings, features and match data
- a plain team member can read team context and roster but receives no management capabilities
- a plain team member cannot update fixtures
- a club owner with no team membership can manage the team's fixtures, players and Subs
- an explicitly delegated `match` permission grants Match management without granting unrelated management permissions
- helper functions introduced for Core access are not executable by the anonymous role

Do not add a new frontend role check without first extending this contract.
