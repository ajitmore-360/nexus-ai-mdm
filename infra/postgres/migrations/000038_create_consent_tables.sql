-- ============================================================================
-- Nexus MDM — Consent Management Tables
-- Migration: 000037
-- ============================================================================
-- Tracks data-subject consent per entity, consent type, and legal basis.
-- Required for GDPR Article 6 (lawfulness of processing) and Article 7
-- (conditions for consent).
--
-- Consent records are NEVER hard-deleted; withdrawal is recorded via
-- withdrawn_at timestamp so the audit trail is preserved.
-- ============================================================================

-- ── Consent records ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS core_mdm.consent_records (
    consent_id      UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID        NOT NULL,
    entity_id       UUID        NOT NULL,

    -- What type of processing the data subject consented to / withdrew from
    -- Values: 'marketing', 'analytics', 'profiling', 'third_party_share',
    --         'automated_decision', 'research', 'service_provision'
    consent_type    VARCHAR(60) NOT NULL,

    -- GDPR Art.6 legal basis:
    -- 'consent', 'legitimate_interest', 'contract', 'legal_obligation',
    -- 'vital_interests', 'public_task'
    legal_basis     VARCHAR(50) NOT NULL DEFAULT 'consent',

    consent_given   BOOLEAN     NOT NULL,

    -- Free-text description of the specific purpose of processing
    purpose         TEXT,

    -- How consent was collected (e.g. 'web_form', 'api', 'import', 'verbal')
    source          TEXT,

    -- Timestamps
    granted_at      TIMESTAMPTZ,              -- NULL if initial state is withdrawn
    withdrawn_at    TIMESTAMPTZ,              -- NULL if still active
    expires_at      TIMESTAMPTZ,              -- NULL means no expiry

    -- Who submitted this consent record
    recorded_by     TEXT,

    metadata        JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Indexes ───────────────────────────────────────────────────────────────────
-- Look up all consent records for an entity (most common query)
CREATE INDEX IF NOT EXISTS idx_consent_entity_tenant
    ON core_mdm.consent_records(entity_id, tenant_id);

-- Query active consents of a specific type across the tenant
CREATE INDEX IF NOT EXISTS idx_consent_active_by_type
    ON core_mdm.consent_records(tenant_id, consent_type)
    WHERE consent_given = true AND withdrawn_at IS NULL;

-- Audit query: recently modified consent records
CREATE INDEX IF NOT EXISTS idx_consent_updated
    ON core_mdm.consent_records(tenant_id, updated_at DESC);

-- ── RLS ───────────────────────────────────────────────────────────────────────
ALTER TABLE core_mdm.consent_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY consent_records_tenant_isolation
    ON core_mdm.consent_records
    USING (tenant_id = current_setting('nexus.tenant_id', true)::uuid);

GRANT SELECT, INSERT, UPDATE ON core_mdm.consent_records TO nexus_app;

-- ── Audit trigger ─────────────────────────────────────────────────────────────
-- Auto-update updated_at on row change
CREATE OR REPLACE FUNCTION core_mdm.touch_consent_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_consent_updated_at
    BEFORE UPDATE ON core_mdm.consent_records
    FOR EACH ROW EXECUTE FUNCTION core_mdm.touch_consent_updated_at();

-- ── Helper view: active consents ──────────────────────────────────────────────
CREATE OR REPLACE VIEW core_mdm.active_consents AS
SELECT *
FROM core_mdm.consent_records
WHERE consent_given  = true
  AND withdrawn_at   IS NULL
  AND (expires_at    IS NULL OR expires_at > NOW());

GRANT SELECT ON core_mdm.active_consents TO nexus_app;

COMMENT ON TABLE core_mdm.consent_records IS
'GDPR consent records per data subject entity. '
'Withdrawal is recorded via withdrawn_at — records are never deleted.';
