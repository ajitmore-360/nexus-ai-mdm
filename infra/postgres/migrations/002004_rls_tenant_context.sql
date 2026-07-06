-- ============================================================================
-- Migration 002004: Activate Row-Level Security via application tenant context
--
-- Until now nexus_app had BYPASSRLS set, making all RLS policies inactive.
-- This migration:
--   1. Replaces app_context.set_tenant with a LOCAL (transaction-scoped) version
--      so the context is never shared between pooled connections.
--   2. Removes BYPASSRLS from nexus_app — RLS policies are now enforced.
--   3. The application layer MUST call app_context.set_tenant(tenant_id) at the
--      start of every transaction that touches tenant-scoped tables.
--
-- All entity_repository, matching_repository, golden_record_repository methods
--  already use transactions for writes and have been updated to call set_tenant.
--  Read-only queries are wrapped in explicit transactions by the Rust helpers
--  in services/mdm-core/src/db/tenant_context.rs.
-- ============================================================================

-- ── 1. Replace set_tenant with a LOCAL (transaction-scoped) variant ──────────
-- Using is_local=true means the setting is automatically reset at COMMIT/ROLLBACK,
-- so no connection-pool leakage is possible even with connection reuse.

CREATE OR REPLACE FUNCTION app_context.set_tenant(tenant UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('app.current_tenant', tenant::TEXT, true);  -- true = transaction-local
END;
$$;

-- ── 2. Also expose as a set_returning variant for use inside SELECT lists ─────
CREATE OR REPLACE FUNCTION app_context.set_tenant_returning(tenant UUID)
RETURNS UUID
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('app.current_tenant', tenant::TEXT, true);
    RETURN tenant;
END;
$$;

-- ── 3. Remove BYPASSRLS from nexus_app ───────────────────────────────────────
-- After this change every SQL statement executed by the application goes through
-- the RLS policies defined on tenant-scoped tables.  The policy USING clause
--   tenant_id = current_setting('app.current_tenant', true)::uuid
-- means queries return zero rows when set_tenant has not been called — which is
-- correct behaviour (defence in depth on top of the WHERE tenant_id = $1 clauses
-- that already exist in every repository query).
ALTER ROLE nexus_app NOBYPASSRLS;
