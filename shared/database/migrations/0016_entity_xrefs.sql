-- Migration 0016: Cross-Reference / ID Mapping Registry
-- Maps MDM golden record IDs to source system local IDs.
-- Example: Customer "Acme Corp" = SAP BP 100234 = Salesforce Account 001Ab000...
-- The unique index on (tenant_id, source_system, external_id) ensures one MDM
-- entity per source-system external ID — no cross-tenant or dual-mapping ambiguity.

CREATE TABLE IF NOT EXISTS core_mdm.entity_xrefs (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    entity_id       UUID         NOT NULL REFERENCES core_mdm.entities(id) ON DELETE CASCADE,
    source_system   VARCHAR(100) NOT NULL,
    external_id     VARCHAR(500) NOT NULL,
    external_type   VARCHAR(100),
    metadata        JSONB        NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_xref_tenant_source_external UNIQUE (tenant_id, source_system, external_id)
);

CREATE INDEX IF NOT EXISTS idx_entity_xrefs_entity   ON core_mdm.entity_xrefs (tenant_id, entity_id);
CREATE INDEX IF NOT EXISTS idx_entity_xrefs_source   ON core_mdm.entity_xrefs (tenant_id, source_system);
CREATE INDEX IF NOT EXISTS idx_entity_xrefs_external ON core_mdm.entity_xrefs (external_id, source_system);

ALTER TABLE core_mdm.entity_xrefs ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON core_mdm.entity_xrefs
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);
