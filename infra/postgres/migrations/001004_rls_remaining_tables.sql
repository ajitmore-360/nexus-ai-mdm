-- ============================================================================
-- Migration 001004: RLS for remaining tenant-scoped tables
--
-- Covers two gaps left after 001003:
--
-- (a) Tables that had ENABLE ROW LEVEL SECURITY in 000031 but were never
--     given a CREATE POLICY â€” PostgreSQL default-deny means azile_readonly
--     (no BYPASSRLS) sees zero rows for these tables.
--
-- (b) Tenant-scoped tables that have no RLS at all â€” missing ENABLE and
--     no policy â€” exposing cross-tenant data to direct DB connections and
--     to azile_readonly.
--
-- azile_app has BYPASSRLS (granted in 001003) so the service account is
-- unaffected by these changes. All new policies follow the same
-- current_setting('app.current_tenant', true)::uuid pattern used
-- throughout the rest of the schema.
-- ============================================================================

-- â”€â”€ (a) Tables with ENABLE but no policy â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- entity_attributes: PII attribute values keyed per entity per tenant
CREATE POLICY entity_attributes_tenant_policy
    ON core_mdm.entity_attributes
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- golden_records: synthesised golden record per tenant
CREATE POLICY golden_records_tenant_policy
    ON core_mdm.golden_records
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- â”€â”€ (b) Tables with no RLS at all â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- users
ALTER TABLE core_mdm.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE core_mdm.users FORCE ROW LEVEL SECURITY;

CREATE POLICY users_tenant_policy
    ON core_mdm.users
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- golden_record_attributes: survivorship-selected attribute values
ALTER TABLE core_mdm.golden_record_attributes ENABLE ROW LEVEL SECURITY;
ALTER TABLE core_mdm.golden_record_attributes FORCE ROW LEVEL SECURITY;

CREATE POLICY golden_record_attributes_tenant_policy
    ON core_mdm.golden_record_attributes
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- audit.audit_logs: tenant audit trail
ALTER TABLE audit.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.audit_logs FORCE ROW LEVEL SECURITY;

CREATE POLICY audit_logs_tenant_policy
    ON audit.audit_logs
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- lineage.entity_lineage: data provenance graph
ALTER TABLE lineage.entity_lineage ENABLE ROW LEVEL SECURITY;
ALTER TABLE lineage.entity_lineage FORCE ROW LEVEL SECURITY;

CREATE POLICY entity_lineage_tenant_policy
    ON lineage.entity_lineage
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- platform.revoked_tokens: per-tenant JWT revocation list
ALTER TABLE platform.revoked_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform.revoked_tokens FORCE ROW LEVEL SECURITY;

CREATE POLICY revoked_tokens_tenant_policy
    ON platform.revoked_tokens
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- event_store.outbox_dlq: failed outbox events awaiting retry
ALTER TABLE event_store.outbox_dlq ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_store.outbox_dlq FORCE ROW LEVEL SECURITY;

CREATE POLICY outbox_dlq_tenant_policy
    ON event_store.outbox_dlq
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- core_mdm.source_systems: source system registry (tenant-scoped)
ALTER TABLE core_mdm.source_systems ENABLE ROW LEVEL SECURITY;
ALTER TABLE core_mdm.source_systems FORCE ROW LEVEL SECURITY;

CREATE POLICY source_systems_tenant_policy
    ON core_mdm.source_systems
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- core_mdm.match_records: matched entity pairs
ALTER TABLE core_mdm.match_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE core_mdm.match_records FORCE ROW LEVEL SECURITY;

CREATE POLICY match_records_tenant_policy
    ON core_mdm.match_records
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- core_mdm.entity_sequences: tenant-scoped auto-numbering sequences
ALTER TABLE core_mdm.entity_sequences ENABLE ROW LEVEL SECURITY;
ALTER TABLE core_mdm.entity_sequences FORCE ROW LEVEL SECURITY;

CREATE POLICY entity_sequences_tenant_policy
    ON core_mdm.entity_sequences
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- core_mdm.attribute_schemas: global defaults (tenant_id IS NULL) + tenant overrides.
-- The policy exposes rows where tenant_id matches the current tenant OR is NULL
-- (global defaults that are visible to all tenants).
ALTER TABLE core_mdm.attribute_schemas ENABLE ROW LEVEL SECURITY;
ALTER TABLE core_mdm.attribute_schemas FORCE ROW LEVEL SECURITY;

CREATE POLICY attribute_schemas_tenant_policy
    ON core_mdm.attribute_schemas
    USING (
        tenant_id IS NULL
        OR tenant_id = current_setting('app.current_tenant', true)::uuid
    );

-- ai.rag_documents: RAG knowledge base (tenant-scoped)
ALTER TABLE ai.rag_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai.rag_documents FORCE ROW LEVEL SECURITY;

CREATE POLICY rag_documents_tenant_policy
    ON ai.rag_documents
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);
