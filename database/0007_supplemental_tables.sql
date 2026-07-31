-- =============================================================================
-- Migration: 0007_supplemental_tables
-- Adds tables required for matching review, data lineage, and consent
-- management that are not covered by earlier migrations.
-- All statements are idempotent (CREATE IF NOT EXISTS).
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- MATCH RECORDS  (core_mdm.match_records)
-- Records every candidate pair surfaced by the matching engine.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.match_records (
    match_id       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id      UUID        NOT NULL,
    entity_id_1    UUID        NOT NULL,
    entity_id_2    UUID        NOT NULL,
    match_score    FLOAT4      NOT NULL DEFAULT 0.0,
    -- Pending / Accepted / Rejected / AutoMerged
    status         TEXT        NOT NULL DEFAULT 'Pending',
    reviewed_by    UUID,
    review_notes   TEXT,
    metadata       JSONB       NOT NULL DEFAULT '{}',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, entity_id_1, entity_id_2)
);

CREATE INDEX IF NOT EXISTS idx_match_records_tenant_status
    ON core_mdm.match_records (tenant_id, status);

CREATE INDEX IF NOT EXISTS idx_match_records_entity
    ON core_mdm.match_records (tenant_id, entity_id_1, entity_id_2);

-- ─────────────────────────────────────────────────────────────────────────────
-- ENTITY LINEAGE  (lineage.entity_lineage)
-- Directed graph of data provenance edges (merge, enrich, derive).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE SCHEMA IF NOT EXISTS lineage;

CREATE TABLE IF NOT EXISTS lineage.entity_lineage (
    lineage_id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID        NOT NULL,
    source_entity_id  UUID        NOT NULL,
    target_entity_id  UUID        NOT NULL,
    -- merged_into | enriched | derived | cloned | split
    lineage_type      TEXT        NOT NULL,
    metadata          JSONB       NOT NULL DEFAULT '{}',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lineage_source
    ON lineage.entity_lineage (tenant_id, source_entity_id);

CREATE INDEX IF NOT EXISTS idx_lineage_target
    ON lineage.entity_lineage (tenant_id, target_entity_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- CONSENT RECORDS  (core_mdm.consent_records)
-- GDPR Article 6/7 consent tracking; withdrawal is immutable (withdrawn_at).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.consent_records (
    consent_id      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL,
    entity_id       UUID        NOT NULL,
    consent_type    TEXT        NOT NULL,
    legal_basis     TEXT        NOT NULL DEFAULT 'consent',
    consent_given   BOOLEAN     NOT NULL,
    purpose         TEXT,
    source          TEXT,
    granted_at      TIMESTAMPTZ,
    withdrawn_at    TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ,
    recorded_by     TEXT,
    metadata        JSONB       NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_consent_entity_tenant
    ON core_mdm.consent_records (entity_id, tenant_id);

CREATE INDEX IF NOT EXISTS idx_consent_active_by_type
    ON core_mdm.consent_records (tenant_id, consent_type)
    WHERE consent_given = true AND withdrawn_at IS NULL;
