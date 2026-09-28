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
- access

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
- access

`access` controls the Access Management surface. It is included by default for Team Admin / Manager, but not Coach. It can be delegated through an Access Level.

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
- `can_manage_access(team_id)`
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
- Access Management: `can_manage_access`

## RLS rules

A team-only member can now resolve the club and season required to render Core.

A team member can read players linked to their team. A user with Players management capability can read the wider club player pool so existing players can be reused without creating duplicates.

Club owners/admins and platform admins receive the same team access through RLS that the frontend advertises.

Fixture writes, team settings, team features, training writes and player-management writes use the matching capability helper.

## Access Management

Football PA uses one shared access engine for all teams.

- `team_memberships` remains the authoritative team account link.
- Reusable team-specific `team_access_levels` provide HybridOne-style permission bundles without creating a second permission matrix.
- If a team membership has an `access_level_id`, that level's permissions are authoritative for the team. Existing memberships without a level retain the legacy role/default-permission behaviour.
- Standard levels are seeded per team: **Team Admin**, **Manager**, **Coach**, and **Treasurer**.
- Team Admin / Manager have `access` by default. Coach and Treasurer do not unless an assigned Access Level explicitly grants it.
- Staff invitations are staged in `pending_team_access`. New Auth users receive the staged team role/access level through the existing Auth-user trigger; an existing Football PA account can be activated directly for the team.
- Removing staff access deactivates only that `team_memberships` row. The person's Auth account and access to other Football PA teams remain intact.
- Player Portal access is a separate PIN/session boundary. Removing a player from portal access disables their `player_portal_credentials` row and deletes active portal sessions, while preserving the player record, match history and statistics.
- The management UI must use `list_team_access_management` and the constrained access-management RPCs rather than direct table writes.

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
