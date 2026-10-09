-- Migration: Role grants and permissions
-- Configures database role permissions for the Supabase service

-- Supabase uses:
-- - authenticated role: logged-in users (via RLS policies)
-- - anon role: anonymous access (public data only, via RLS)
-- - service_role: admin access (backend operations)

-- Note: Specific grant statements will be populated in the next iteration
-- after auditing the live role configuration.
