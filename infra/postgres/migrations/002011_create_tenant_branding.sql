-- ============================================================
-- 002011 — tenant_branding
-- White-label customisation per tenant (Enterprise tier only).
-- ============================================================

CREATE TABLE IF NOT EXISTS core_mdm.tenant_branding (
    tenant_id       UUID PRIMARY KEY
                        REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,
    product_name    TEXT,           -- overrides "Nexus AI MDM" in the UI
    logo_url        TEXT,           -- absolute URL to the tenant logo
    favicon_url     TEXT,           -- absolute URL to the favicon
    primary_color   TEXT,           -- hex string e.g. '#00C896'
    accent_color    TEXT,           -- hex string e.g. '#6366F1'
    support_email   TEXT,
    support_url     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Index ────────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_tenant_branding_tenant_id
    ON core_mdm.tenant_branding(tenant_id);

-- ── RLS ─────────────────────────────────────────────────────────────────────

ALTER TABLE core_mdm.tenant_branding ENABLE ROW LEVEL SECURITY;

-- Each tenant may only see and modify its own branding row.
CREATE POLICY tenant_branding_isolation
    ON core_mdm.tenant_branding
    USING (tenant_id = current_setting('app.current_tenant', TRUE)::UUID);
