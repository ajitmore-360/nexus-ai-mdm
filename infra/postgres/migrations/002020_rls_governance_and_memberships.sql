-- ============================================================================
-- Migration 002020: Row-Level Security for governance tables and
--                   tenant_memberships
--
-- Migration 002019 added entity_type_assignments and entity_approval_requests
-- without RLS.  Migration 002018 added tenant_memberships without RLS.
-- Application code already filters every query by tenant_id, but DB-level
-- RLS provides defence-in-depth.
-- ============================================================================

-- ── entity_type_assignments ──────────────────────────────────────────────────

ALTER TABLE core_mdm.entity_type_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE core_mdm.entity_type_assignments FORCE  ROW LEVEL SECURITY;

CREATE POLICY eta_tenant_policy
    ON core_mdm.entity_type_assignments
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- ── entity_approval_requests ─────────────────────────────────────────────────

ALTER TABLE core_mdm.entity_approval_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE core_mdm.entity_approval_requests FORCE  ROW LEVEL SECURITY;

CREATE POLICY ear_tenant_policy
    ON core_mdm.entity_approval_requests
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- ── tenant_memberships ────────────────────────────────────────────────────────
-- A user's memberships in other tenants must not be visible when querying
-- within tenant A.  The policy restricts reads to the current tenant's
-- membership rows only.

ALTER TABLE core_mdm.tenant_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE core_mdm.tenant_memberships FORCE  ROW LEVEL SECURITY;

CREATE POLICY memberships_tenant_policy
    ON core_mdm.tenant_memberships
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);
