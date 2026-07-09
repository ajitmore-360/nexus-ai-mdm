-- Migration: 002021_entity_blocking_keys
-- Pre-computed blocking keys for entity matching.
-- Stores derived keys (Soundex phonetic codes, etc.) so blocking lookups
-- are a single indexed point query instead of computing derivations at query time.

CREATE TABLE IF NOT EXISTS core_mdm.entity_blocking_keys (
    id            BIGSERIAL    PRIMARY KEY,
    tenant_id     UUID         NOT NULL,
    entity_id     UUID         NOT NULL REFERENCES core_mdm.entities(entity_id) ON DELETE CASCADE,
    blocking_type TEXT         NOT NULL,  -- e.g. 'PHONETIC'
    blocking_value TEXT        NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, entity_id, blocking_type, blocking_value)
);

-- Primary lookup pattern: find all entities that share a given (type, value) pair.
CREATE INDEX idx_entity_blocking_keys_lookup
    ON core_mdm.entity_blocking_keys (tenant_id, blocking_type, blocking_value);

-- Enable RLS so tenants cannot see each other's blocking keys.
ALTER TABLE core_mdm.entity_blocking_keys ENABLE ROW LEVEL SECURITY;

CREATE POLICY entity_blocking_keys_tenant_isolation
    ON core_mdm.entity_blocking_keys
    AS PERMISSIVE FOR ALL
    USING      (tenant_id = current_setting('app.current_tenant', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- Allow the app role full access (RLS enforces isolation).
GRANT SELECT, INSERT, UPDATE, DELETE
    ON core_mdm.entity_blocking_keys TO azile_app;
GRANT USAGE, SELECT
    ON SEQUENCE core_mdm.entity_blocking_keys_id_seq TO azile_app;
