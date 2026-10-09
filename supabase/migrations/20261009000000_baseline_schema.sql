-- Migration: baseline_schema
-- Creates all core tables, columns, constraints, and indexes
-- Generated from live Supabase project


-- ============================================================================
-- TABLES
-- ============================================================================

create table if not exists public.profiles (
  id uuid not null,
  display_name text,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.clubs (
  id uuid not null default gen_random_uuid(),
  name text not null,
  slug text not null,
  short_name text,
  badge_url text,
  primary_colour text,
  secondary_colour text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (id),
  unique (slug)
);

create table if not exists public.teams (
  id uuid not null default gen_random_uuid(),
  club_id uuid not null,
  name text not null,
  slug text not null,
  season_label text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  age_group text,
  gender text,
  match_format text,
  badge_url text
,
  primary key (id)
);

create table if not exists public.club_memberships (
  id uuid not null default gen_random_uuid(),
  club_id uuid not null,
  user_id uuid not null,
  role text not null default 'member'::text,
  permissions ARRAY not null default '{}'::text[],
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.team_memberships (
  id uuid not null default gen_random_uuid(),
  team_id uuid not null,
  user_id uuid not null,
  role text not null default 'member'::text,
  permissions ARRAY not null default '{}'::text[],
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  player_id uuid,
  access_level_id uuid
,
  primary key (id)
);

create table if not exists public.seasons (
  id uuid not null default gen_random_uuid(),
  club_id uuid not null,
  label text not null,
  starts_on date,
  ends_on date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.players (
  id uuid not null default gen_random_uuid(),
  club_id uuid not null,
  display_name text not null,
  preferred_position text,
  shirt_number integer,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  first_name text,
  last_name text,
  lineup_alias text
,
  primary key (id)
);

create table if not exists public.team_players (
  id uuid not null default gen_random_uuid(),
  team_id uuid not null,
  player_id uuid not null,
  season_id uuid,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  voting_alias text
,
  primary key (id)
);

create table if not exists public.fixtures (
  id uuid not null default gen_random_uuid(),
  team_id uuid not null,
  season_id uuid,
  opponent text not null,
  venue text not null,
  competition text,
  kick_off timestamptz,
  status text not null default 'scheduled'::text,
  home_score integer,
  away_score integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  external_source text,
  external_id text,
  external_url text,
  ground_name text,
  ground_address text,
  ground_postcode text,
  include_in_stats boolean not null default true
,
  primary key (id)
);

create table if not exists public.competitions (
  id uuid not null default gen_random_uuid(),
  club_id uuid not null,
  name text not null,
  short_name text,
  competition_type text not null default 'league'::text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.match_squads (
  id uuid not null default gen_random_uuid(),
  fixture_id uuid not null,
  player_id uuid not null,
  squad_role text not null default 'outfield'::text,
  selected boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.match_lineups (
  id uuid not null default gen_random_uuid(),
  fixture_id uuid not null,
  player_id uuid not null,
  position_code text,
  starter boolean not null default false,
  sort_order integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.match_events (
  id uuid not null default gen_random_uuid(),
  fixture_id uuid not null,
  event_type text not null,
  player_id uuid,
  related_player_id uuid,
  minute integer,
  stoppage_minute integer not null default 0,
  zone integer,
  team_side text not null default 'us'::text,
  details jsonb not null default '{}'::jsonb,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.substitutions (
  id uuid not null default gen_random_uuid(),
  fixture_id uuid not null,
  player_off_id uuid,
  player_on_id uuid,
  minute integer not null,
  stoppage_minute integer not null default 0,
  created_by uuid,
  created_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.voting_templates (
  id uuid not null default gen_random_uuid(),
  club_id uuid not null,
  team_id uuid,
  name text not null,
  description text,
  audience text not null default 'players'::text,
  allowed_roles ARRAY not null default '{}'::text[],
  anonymous boolean not null default false,
  one_ballot_per_voter boolean not null default true,
  active boolean not null default true,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.voting_questions (
  id uuid not null default gen_random_uuid(),
  template_id uuid not null,
  title text not null,
  description text,
  question_type text not null,
  sort_order integer not null default 0,
  required boolean not null default true,
  min_selections integer not null default 1,
  max_selections integer not null default 1,
  point_scheme jsonb not null default '{}'::jsonb,
  allow_self_vote boolean not null default true,
  reason_mode text not null default 'none'::text,
  candidate_source text not null default 'team_players'::text,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.voting_events (
  id uuid not null default gen_random_uuid(),
  club_id uuid not null,
  team_id uuid not null,
  fixture_id uuid,
  template_id uuid,
  title text not null,
  status text not null default 'draft'::text,
  opens_at timestamptz,
  closes_at timestamptz,
  public_token uuid,
  config_snapshot jsonb not null default '{}'::jsonb,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.voting_ballots (
  id uuid not null default gen_random_uuid(),
  event_id uuid not null,
  voter_user_id uuid,
  voter_key text,
  submitted_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.voting_selections (
  id uuid not null default gen_random_uuid(),
  ballot_id uuid not null,
  question_id uuid not null,
  player_id uuid,
  custom_value text,
  rank integer,
  points numeric not null default 0,
  reason text,
  created_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.subs_settings (
  id uuid not null default gen_random_uuid(),
  club_id uuid not null,
  team_id uuid not null,
  season_id uuid not null,
  charge_model text not null,
  amount_pence integer not null,
  currency text not null default 'GBP'::text,
  active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  payment_url_template text
,
  primary key (id)
);

create table if not exists public.subs_payments (
  id uuid not null default gen_random_uuid(),
  club_id uuid not null,
  team_id uuid not null,
  season_id uuid not null,
  player_id uuid not null,
  amount_pence integer not null,
  paid_at timestamptz not null default now(),
  method text,
  note text,
  created_by uuid,
  created_at timestamptz not null default now(),
  fixture_id uuid
,
  primary key (id)
);

create table if not exists public.match_states (
  id uuid not null default gen_random_uuid(),
  fixture_id uuid not null,
  phase text not null default 'PRE-MATCH'::text,
  elapsed_seconds integer not null default 0,
  running boolean not null default false,
  home_score integer not null default 0,
  away_score integer not null default 0,
  formation text not null default '4-2-3-1'::text,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  current_xi jsonb not null default '{}'::jsonb,
  match_started_at timestamptz,
  running_started_at timestamptz,
  lineup_positions jsonb not null default '{}'::jsonb
,
  primary key (id),
  unique (fixture_id)
);

create table if not exists public.platform_admins (
  user_id uuid not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
,
  primary key (user_id)
);

create table if not exists public.training_sessions (
  id uuid not null default gen_random_uuid(),
  team_id uuid not null,
  session_date date not null,
  title text not null default 'Training'::text,
  notes text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  locked_at timestamptz,
  locked_by uuid
,
  primary key (id)
);

create table if not exists public.training_attendance (
  session_id uuid not null,
  player_id uuid not null,
  status text not null,
  notes text,
  updated_by uuid,
  updated_at timestamptz not null default now()
,
  primary key (session_id, player_id)
);

create table if not exists public.team_settings (
  team_id uuid not null,
  period_type text not null default 'halves'::text,
  period_count integer not null default 2,
  period_minutes integer not null default 45,
  rolling_subs boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  fixture_source text,
  fixture_source_url text,
  fixture_sync_on_login boolean not null default true,
  fixture_last_checked_at timestamptz,
  fixture_external_team_id text,
  fixture_external_season_id text,
  fixture_external_group_key text,
  kit_pattern text not null default 'solid'::text,
  kit_primary_colour text,
  kit_secondary_colour text,
  show_cards boolean not null default true,
  fixture_calendar_token uuid not null default gen_random_uuid(),
  kit_number_colour text default '#FFFFFF'::text,
  scoreboard_token uuid not null default gen_random_uuid(),
  fixture_sync_ignored_updates jsonb not null default '[]'::jsonb,
  capture_assists boolean not null default true,
  nav_order ARRAY not null default ARRAY['home'::text, 'match'::text, 'players'::text, 'fixtures'::text, 'dashboard'::text, 'voting'::text, 'subs'::text, 'live'::text, 'settings'::text],
  goalkeeper_kit_colour text not null default '#F5C518'::text,
  voting_private_report_user_id uuid,
  home_shortcut_1 text not null default 'training'::text,
  home_shortcut_2 text not null default 'dashboard'::text,
  player_portal_token uuid not null default gen_random_uuid(),
  player_portal_legacy_open boolean not null default false
,
  primary key (team_id)
);

create table if not exists public.team_features (
  team_id uuid not null,
  players boolean not null default true,
  training boolean not null default true,
  availability boolean not null default true,
  match_centre boolean not null default true,
  voting boolean not null default true,
  subs_finance boolean not null default true,
  awards boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid
,
  primary key (team_id)
);

create table if not exists public.player_portal_credentials (
  team_id uuid not null,
  player_id uuid not null,
  legacy_login_name text,
  pin_hash text not null,
  pin_chosen boolean not null default true,
  date_of_birth date,
  active boolean not null default true,
  failed_attempts integer not null default 0,
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (team_id, player_id)
);

create table if not exists public.player_portal_sessions (
  token_hash text not null,
  team_id uuid not null,
  player_id uuid not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
,
  primary key (token_hash)
);

create table if not exists public.player_season_snapshots (
  team_id uuid not null,
  season_id uuid not null,
  player_id uuid not null,
  appearances integer not null default 0,
  starts integer,
  minutes integer not null default 0,
  goals integer not null default 0,
  assists integer not null default 0,
  clean_sheets integer,
  source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (team_id, season_id, player_id)
);

create table if not exists public.pending_team_access (
  id uuid not null default gen_random_uuid(),
  team_id uuid not null,
  email text not null,
  role text not null default 'manager'::text,
  permissions ARRAY not null default '{}'::text[],
  player_id uuid,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  access_level_id uuid,
  created_by uuid,
  updated_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.team_domains (
  id uuid not null default gen_random_uuid(),
  team_id uuid not null,
  hostname text not null,
  primary_domain boolean not null default true,
  active boolean not null default true,
  team_name text not null,
  club_name text not null,
  badge_url text,
  primary_colour text,
  secondary_colour text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (id),
  unique (hostname)
);

create table if not exists public.subs_fixture_statuses (
  id uuid not null default gen_random_uuid(),
  club_id uuid not null,
  team_id uuid not null,
  season_id uuid not null,
  fixture_id uuid not null,
  player_id uuid not null,
  status text not null,
  note text,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.fixture_availability_polls (
  fixture_id uuid not null,
  team_id uuid not null,
  season_id uuid,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (fixture_id)
);

create table if not exists public.fixture_availability_responses (
  id uuid not null default gen_random_uuid(),
  fixture_id uuid not null,
  team_id uuid not null,
  season_id uuid,
  player_id uuid not null,
  available boolean not null,
  responded_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.team_access_levels (
  id uuid not null default gen_random_uuid(),
  team_id uuid not null,
  name text not null,
  description text,
  permissions ARRAY not null default '{}'::text[],
  active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
,
  primary key (id)
);

create table if not exists public.team_invite_links (
  id uuid not null default gen_random_uuid(),
  team_id uuid not null,
  access_level_id uuid not null,
  role text not null,
  token_hash text not null,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  used_by uuid
,
  primary key (id),
  unique (token_hash)
);

-- ============================================================================
-- FOREIGN KEY CONSTRAINTS
-- ============================================================================

-- Skipping foreign key profiles_id_fkey (references external auth schema)
alter table public.clubs
  add constraint players_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.clubs
  add constraint subs_fixture_statuses_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.clubs
  add constraint subs_payments_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.clubs
  add constraint subs_settings_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.clubs
  add constraint seasons_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.clubs
  add constraint club_memberships_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.clubs
  add constraint voting_events_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.clubs
  add constraint voting_templates_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.clubs
  add constraint teams_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.clubs
  add constraint competitions_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.teams
  add constraint player_portal_sessions_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint subs_payments_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint team_invite_links_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint team_access_levels_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint fixture_availability_responses_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint fixture_availability_polls_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint voting_events_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint subs_fixture_statuses_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint team_domains_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint pending_team_access_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint voting_templates_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint fixtures_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint team_players_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint team_memberships_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint teams_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.teams
  add constraint player_season_snapshots_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint player_portal_credentials_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint team_features_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint team_settings_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint training_sessions_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.teams
  add constraint subs_settings_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.club_memberships
  add constraint club_memberships_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

-- Skipping foreign key club_memberships_user_id_fkey (references external auth schema)
-- Skipping foreign key team_memberships_user_id_fkey (references external auth schema)
alter table public.team_memberships
  add constraint team_memberships_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.team_memberships
  add constraint team_memberships_access_level_id_fkey
  foreign key (access_level_id)
  references public.team_access_levels (id);

alter table public.team_memberships
  add constraint team_memberships_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.seasons
  add constraint fixture_availability_responses_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

alter table public.seasons
  add constraint player_season_snapshots_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

alter table public.seasons
  add constraint team_players_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

alter table public.seasons
  add constraint seasons_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.seasons
  add constraint fixtures_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

alter table public.seasons
  add constraint subs_settings_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

alter table public.seasons
  add constraint subs_payments_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

alter table public.seasons
  add constraint fixture_availability_polls_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

alter table public.seasons
  add constraint subs_fixture_statuses_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

alter table public.players
  add constraint subs_payments_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.players
  add constraint players_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.players
  add constraint team_players_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.players
  add constraint match_squads_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.players
  add constraint match_lineups_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.players
  add constraint match_events_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.players
  add constraint match_events_related_player_id_fkey
  foreign key (related_player_id)
  references public.players (id);

alter table public.players
  add constraint substitutions_player_off_id_fkey
  foreign key (player_off_id)
  references public.players (id);

alter table public.players
  add constraint substitutions_player_on_id_fkey
  foreign key (player_on_id)
  references public.players (id);

alter table public.players
  add constraint voting_selections_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.players
  add constraint team_memberships_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.players
  add constraint training_attendance_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.players
  add constraint player_portal_credentials_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.players
  add constraint player_portal_sessions_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.players
  add constraint player_season_snapshots_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.players
  add constraint pending_team_access_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.players
  add constraint subs_fixture_statuses_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.players
  add constraint fixture_availability_responses_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.team_players
  add constraint team_players_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.team_players
  add constraint team_players_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

alter table public.team_players
  add constraint team_players_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.fixtures
  add constraint fixtures_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

alter table public.fixtures
  add constraint fixture_availability_polls_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.fixtures
  add constraint subs_fixture_statuses_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.fixtures
  add constraint subs_payments_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.fixtures
  add constraint match_states_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.fixtures
  add constraint voting_events_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.fixtures
  add constraint substitutions_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.fixtures
  add constraint match_events_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.fixtures
  add constraint match_lineups_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.fixtures
  add constraint match_squads_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.fixtures
  add constraint fixtures_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.competitions
  add constraint competitions_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.match_squads
  add constraint match_squads_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.match_squads
  add constraint match_squads_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.match_lineups
  add constraint match_lineups_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.match_lineups
  add constraint match_lineups_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.match_events
  add constraint match_events_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.match_events
  add constraint match_events_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.match_events
  add constraint match_events_related_player_id_fkey
  foreign key (related_player_id)
  references public.players (id);

-- Skipping foreign key match_events_created_by_fkey (references external auth schema)
alter table public.substitutions
  add constraint substitutions_player_off_id_fkey
  foreign key (player_off_id)
  references public.players (id);

-- Skipping foreign key substitutions_created_by_fkey (references external auth schema)
alter table public.substitutions
  add constraint substitutions_player_on_id_fkey
  foreign key (player_on_id)
  references public.players (id);

alter table public.substitutions
  add constraint substitutions_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.voting_templates
  add constraint voting_events_template_id_fkey
  foreign key (template_id)
  references public.voting_templates (id);

alter table public.voting_templates
  add constraint voting_questions_template_id_fkey
  foreign key (template_id)
  references public.voting_templates (id);

alter table public.voting_templates
  add constraint voting_templates_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.voting_templates
  add constraint voting_templates_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.voting_questions
  add constraint voting_selections_question_id_fkey
  foreign key (question_id)
  references public.voting_questions (id);

alter table public.voting_questions
  add constraint voting_questions_template_id_fkey
  foreign key (template_id)
  references public.voting_templates (id);

alter table public.voting_events
  add constraint voting_events_template_id_fkey
  foreign key (template_id)
  references public.voting_templates (id);

alter table public.voting_events
  add constraint voting_events_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.voting_events
  add constraint voting_events_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.voting_events
  add constraint voting_events_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.voting_events
  add constraint voting_ballots_event_id_fkey
  foreign key (event_id)
  references public.voting_events (id);

-- Skipping foreign key voting_events_created_by_fkey (references external auth schema)
alter table public.voting_ballots
  add constraint voting_ballots_event_id_fkey
  foreign key (event_id)
  references public.voting_events (id);

alter table public.voting_ballots
  add constraint voting_selections_ballot_id_fkey
  foreign key (ballot_id)
  references public.voting_ballots (id);

-- Skipping foreign key voting_ballots_voter_user_id_fkey (references external auth schema)
alter table public.voting_selections
  add constraint voting_selections_ballot_id_fkey
  foreign key (ballot_id)
  references public.voting_ballots (id);

alter table public.voting_selections
  add constraint voting_selections_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.voting_selections
  add constraint voting_selections_question_id_fkey
  foreign key (question_id)
  references public.voting_questions (id);

alter table public.subs_settings
  add constraint subs_settings_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.subs_settings
  add constraint subs_settings_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.subs_settings
  add constraint subs_settings_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

-- Skipping foreign key subs_settings_created_by_fkey (references external auth schema)
alter table public.subs_payments
  add constraint subs_payments_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.subs_payments
  add constraint subs_payments_player_id_fkey
  foreign key (player_id)
  references public.players (id);

-- Skipping foreign key subs_payments_created_by_fkey (references external auth schema)
alter table public.subs_payments
  add constraint subs_payments_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.subs_payments
  add constraint subs_payments_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.subs_payments
  add constraint subs_payments_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

alter table public.match_states
  add constraint match_states_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

-- Skipping foreign key match_states_updated_by_fkey (references external auth schema)
-- Skipping foreign key platform_admins_user_id_fkey (references external auth schema)
alter table public.training_sessions
  add constraint training_sessions_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

-- Skipping foreign key training_sessions_created_by_fkey (references external auth schema)
alter table public.training_sessions
  add constraint training_attendance_session_id_fkey
  foreign key (session_id)
  references public.training_sessions (id);

alter table public.training_attendance
  add constraint training_attendance_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.training_attendance
  add constraint training_attendance_session_id_fkey
  foreign key (session_id)
  references public.training_sessions (id);

-- Skipping foreign key training_attendance_updated_by_fkey (references external auth schema)
alter table public.team_settings
  add constraint team_settings_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

-- Skipping foreign key team_settings_voting_private_report_user_id_fkey (references external auth schema)
-- Skipping foreign key team_settings_updated_by_fkey (references external auth schema)
alter table public.team_features
  add constraint team_features_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

-- Skipping foreign key team_features_updated_by_fkey (references external auth schema)
alter table public.player_portal_credentials
  add constraint player_portal_credentials_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.player_portal_credentials
  add constraint player_portal_credentials_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.player_portal_sessions
  add constraint player_portal_sessions_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.player_portal_sessions
  add constraint player_portal_sessions_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.player_season_snapshots
  add constraint player_season_snapshots_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.player_season_snapshots
  add constraint player_season_snapshots_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.player_season_snapshots
  add constraint player_season_snapshots_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

-- Skipping foreign key pending_team_access_created_by_fkey (references external auth schema)
alter table public.pending_team_access
  add constraint pending_team_access_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.pending_team_access
  add constraint pending_team_access_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.pending_team_access
  add constraint pending_team_access_access_level_id_fkey
  foreign key (access_level_id)
  references public.team_access_levels (id);

alter table public.team_domains
  add constraint team_domains_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.subs_fixture_statuses
  add constraint subs_fixture_statuses_player_id_fkey
  foreign key (player_id)
  references public.players (id);

-- Skipping foreign key subs_fixture_statuses_updated_by_fkey (references external auth schema)
alter table public.subs_fixture_statuses
  add constraint subs_fixture_statuses_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.subs_fixture_statuses
  add constraint subs_fixture_statuses_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

alter table public.subs_fixture_statuses
  add constraint subs_fixture_statuses_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.subs_fixture_statuses
  add constraint subs_fixture_statuses_club_id_fkey
  foreign key (club_id)
  references public.clubs (id);

alter table public.fixture_availability_polls
  add constraint fixture_availability_polls_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

alter table public.fixture_availability_polls
  add constraint fixture_availability_polls_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixtures (id);

alter table public.fixture_availability_polls
  add constraint fixture_availability_responses_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixture_availability_polls (fixture_id);

alter table public.fixture_availability_polls
  add constraint fixture_availability_polls_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.fixture_availability_responses
  add constraint fixture_availability_responses_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.fixture_availability_responses
  add constraint fixture_availability_responses_player_id_fkey
  foreign key (player_id)
  references public.players (id);

alter table public.fixture_availability_responses
  add constraint fixture_availability_responses_season_id_fkey
  foreign key (season_id)
  references public.seasons (id);

alter table public.fixture_availability_responses
  add constraint fixture_availability_responses_fixture_id_fkey
  foreign key (fixture_id)
  references public.fixture_availability_polls (fixture_id);

alter table public.team_access_levels
  add constraint team_access_levels_team_id_fkey
  foreign key (team_id)
  references public.teams (id);

alter table public.team_access_levels
  add constraint team_invite_links_access_level_id_fkey
  foreign key (access_level_id)
  references public.team_access_levels (id);

alter table public.team_access_levels
  add constraint pending_team_access_access_level_id_fkey
  foreign key (access_level_id)
  references public.team_access_levels (id);

-- Skipping foreign key team_access_levels_created_by_fkey (references external auth schema)
alter table public.team_access_levels
  add constraint team_memberships_access_level_id_fkey
  foreign key (access_level_id)
  references public.team_access_levels (id);

alter table public.team_invite_links
  add constraint team_invite_links_access_level_id_fkey
  foreign key (access_level_id)
  references public.team_access_levels (id);

alter table public.team_invite_links
  add constraint team_invite_links_team_id_fkey
  foreign key (team_id)
  references public.teams (id);


-- ============================================================================
-- ENABLE RLS (Row Level Security)
-- ============================================================================

alter table public.profiles enable row level security;
alter table public.clubs enable row level security;
alter table public.teams enable row level security;
alter table public.club_memberships enable row level security;
alter table public.team_memberships enable row level security;
alter table public.seasons enable row level security;
alter table public.players enable row level security;
alter table public.team_players enable row level security;
alter table public.fixtures enable row level security;
alter table public.competitions enable row level security;
alter table public.match_squads enable row level security;
alter table public.match_lineups enable row level security;
alter table public.match_events enable row level security;
alter table public.substitutions enable row level security;
alter table public.voting_templates enable row level security;
alter table public.voting_questions enable row level security;
alter table public.voting_events enable row level security;
alter table public.voting_ballots enable row level security;
alter table public.voting_selections enable row level security;
alter table public.subs_settings enable row level security;
alter table public.subs_payments enable row level security;
alter table public.match_states enable row level security;
alter table public.platform_admins enable row level security;
alter table public.training_sessions enable row level security;
alter table public.training_attendance enable row level security;
alter table public.team_settings enable row level security;
alter table public.team_features enable row level security;
alter table public.player_portal_credentials enable row level security;
alter table public.player_portal_sessions enable row level security;
alter table public.player_season_snapshots enable row level security;
alter table public.pending_team_access enable row level security;
alter table public.team_domains enable row level security;
alter table public.subs_fixture_statuses enable row level security;
alter table public.fixture_availability_polls enable row level security;
alter table public.fixture_availability_responses enable row level security;
alter table public.team_access_levels enable row level security;
alter table public.team_invite_links enable row level security;
