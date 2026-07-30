-- Stores per-tenant, per-entity-type blocking rule sets for the match engine.
-- Rules are JSON strings like "exact:email", "phonetic:legal_name", "vector".
-- When a row exists for (tenant_id, entity_type_code) the engine uses it;
-- otherwise the worker falls back to its hardcoded defaults.
CREATE TABLE IF NOT EXISTS core_mdm.entity_type_blocking_rules (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL,
    entity_type_code TEXT        NOT NULL,
    rules            JSONB       NOT NULL DEFAULT '[]'::jsonb,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, entity_type_code)
);

CREATE INDEX IF NOT EXISTS idx_etbr_tenant_type
    ON core_mdm.entity_type_blocking_rules (tenant_id, entity_type_code);
