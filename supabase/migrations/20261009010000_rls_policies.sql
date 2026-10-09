-- Migration: RLS policies and security functions
-- Enables row-level security policies for all tables

-- NOTE: RLS policies are complex and reference security functions
-- The following policies use helper functions: can_access_club, can_access_team, can_manage_*, etc.
-- These functions must be created before policies in a fresh rebuild.
-- Policy details are documented in SUPABASE_SCHEMA.md

-- Total policies to configure: 56
-- Tables with RLS enabled: 37

