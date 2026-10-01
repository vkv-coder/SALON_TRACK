-- ============================================================================
-- SALON_TRACK — document removal of dormant anon grants
-- ============================================================================
-- Already applied directly against the live database. Committed here purely
-- as a record of what changed — safe to re-run, no-op if already revoked.
--
-- CONTEXT
--   A monthly Supabase RLS/RPC audit (2026-10) swept both Supabase projects
--   for tables where the `anon` role held a raw table GRANT (SELECT/INSERT/
--   UPDATE/DELETE) with no RLS policy actually covering that privilege for
--   anon. In Postgres, that combination is inert the moment it happens —
--   with RLS enabled and no matching policy, the role sees/affects zero
--   rows regardless of the grant. But it's a landmine: if a permissive
--   policy for anon/public is ever added later without someone checking
--   existing grants, the table becomes fully exposed with no further step
--   needed. Every instance below was confirmed dormant (live curl tests
--   with the anon key, before and after) before revoking. Both tables here
--   held real live data (st_admin_secret, st_sessions) despite returning
--   nothing to anon.
-- ============================================================================

REVOKE DELETE, INSERT, SELECT, UPDATE ON public.st_admin_secret FROM anon;
REVOKE DELETE, INSERT, SELECT, UPDATE ON public.st_sessions FROM anon;
