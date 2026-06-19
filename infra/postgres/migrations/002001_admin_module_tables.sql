-- ============================================================
-- 002001: Admin Module — entity types, sequences, attribute
--         schemas, and source system registry
-- ============================================================

-- ── Entity Type Configuration ────────────────────────────────────────────────
-- Defines the entity types a tenant tracks (Customer, Product, Location, etc.)

CREATE TABLE IF NOT EXISTS core_mdm.entity_type_configs (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL,
    name                TEXT        NOT NULL,              -- "Customer"
    code                TEXT        NOT NULL,              -- "CUSTOMER"
    description         TEXT,
    icon                TEXT        DEFAULT '🏢',
    color               TEXT        DEFAULT '#7C3AED',
    -- Number sequence
    seq_prefix          TEXT        NOT NULL,              -- "CUST"
    seq_format          TEXT        NOT NULL DEFAULT '{PREFIX}-{YYYY}-{SEQ5}',
    seq_current         BIGINT      NOT NULL DEFAULT 0,
    seq_reset_period    TEXT        NOT NULL DEFAULT 'never', -- never | yearly | monthly
    seq_last_reset      TIMESTAMPTZ,
    -- Survivorship
    default_match_threshold NUMERIC(4,3) DEFAULT 0.85,
    -- Status
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    is_system           BOOLEAN     NOT NULL DEFAULT FALSE, -- system types can't be deleted
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, code)
);

ALTER TABLE core_mdm.entity_type_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY entity_type_configs_tenant ON core_mdm.entity_type_configs
    USING (tenant_id = current_setting('app.current_tenant', TRUE)::UUID);

CREATE INDEX IF NOT EXISTS idx_entity_type_configs_tenant
    ON core_mdm.entity_type_configs (tenant_id);

-- ── Number Sequence Ledger ───────────────────────────────────────────────────
-- Tracks per-tenant per-entity-type sequence values with optional yearly reset

CREATE TABLE IF NOT EXISTS core_mdm.number_sequences (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL,
    entity_type_code    TEXT        NOT NULL,
    period_key          TEXT        NOT NULL DEFAULT 'global', -- 'global' | '2026' | '2026-06'
    current_value       BIGINT      NOT NULL DEFAULT 0,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, entity_type_code, period_key)
);

ALTER TABLE core_mdm.number_sequences ENABLE ROW LEVEL SECURITY;
CREATE POLICY number_sequences_tenant ON core_mdm.number_sequences
    USING (tenant_id = current_setting('app.current_tenant', TRUE)::UUID);

CREATE INDEX IF NOT EXISTS idx_number_sequences_lookup
    ON core_mdm.number_sequences (tenant_id, entity_type_code, period_key);

-- Atomic next-value function (advisory lock per tenant+type to prevent races)
CREATE OR REPLACE FUNCTION core_mdm.next_sequence_value(
    p_tenant_id         UUID,
    p_entity_type_code  TEXT,
    p_period_key        TEXT DEFAULT 'global'
) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_next BIGINT;
BEGIN
    -- Upsert and return the incremented value atomically
    INSERT INTO core_mdm.number_sequences (tenant_id, entity_type_code, period_key, current_value)
    VALUES (p_tenant_id, p_entity_type_code, p_period_key, 1)
    ON CONFLICT (tenant_id, entity_type_code, period_key)
    DO UPDATE SET
        current_value = core_mdm.number_sequences.current_value + 1,
        updated_at    = NOW()
    RETURNING current_value INTO v_next;

    RETURN v_next;
END;
$$;

-- ── Attribute Schemas ────────────────────────────────────────────────────────
-- Custom attribute definitions per entity type per tenant

CREATE TABLE IF NOT EXISTS core_mdm.attribute_schemas (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL,
    entity_type_code    TEXT        NOT NULL,
    attribute_key       TEXT        NOT NULL,              -- snake_case key stored in JSONB
    display_name        TEXT        NOT NULL,
    description         TEXT,
    data_type           TEXT        NOT NULL,              -- text|number|currency|boolean|date|enum|phone|email|url|address|user|entity
    is_required         BOOLEAN     NOT NULL DEFAULT FALSE,
    is_system           BOOLEAN     NOT NULL DEFAULT FALSE, -- system attrs can't be deleted
    is_pii              BOOLEAN     NOT NULL DEFAULT FALSE,
    is_searchable       BOOLEAN     NOT NULL DEFAULT TRUE,
    display_order       INTEGER     NOT NULL DEFAULT 100,
    -- Validation / constraints
    validation_regex    TEXT,
    min_length          INTEGER,
    max_length          INTEGER,
    enum_values         TEXT[],                            -- for data_type = 'enum'
    default_value       TEXT,
    -- Survivorship weight (higher = more trusted for golden record)
    survivorship_weight NUMERIC(3,2) DEFAULT 1.0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, entity_type_code, attribute_key)
);

ALTER TABLE core_mdm.attribute_schemas ENABLE ROW LEVEL SECURITY;
CREATE POLICY attribute_schemas_tenant ON core_mdm.attribute_schemas
    USING (tenant_id = current_setting('app.current_tenant', TRUE)::UUID);

CREATE INDEX IF NOT EXISTS idx_attribute_schemas_lookup
    ON core_mdm.attribute_schemas (tenant_id, entity_type_code);

-- Seed system base attributes for standard entity types
INSERT INTO core_mdm.attribute_schemas
    (tenant_id, entity_type_code, attribute_key, display_name, data_type, is_required, is_system, is_pii, display_order)
SELECT
    '00000000-0000-0000-0000-000000000000'::UUID, -- placeholder; applied per-tenant at onboard time
    etc.code,
    attr.key,
    attr.display_name,
    attr.data_type,
    attr.is_required,
    TRUE,  -- system
    attr.is_pii,
    attr.display_order
FROM (VALUES
    ('CUSTOMER'), ('SUPPLIER'), ('PRODUCT'), ('LOCATION'), ('CONTACT')
) AS etc(code)
CROSS JOIN (VALUES
    ('full_name',       'Full Name',        'text',    TRUE,  TRUE,  10),
    ('primary_email',   'Primary Email',    'email',   FALSE, TRUE,  20),
    ('phone_number',    'Phone Number',     'phone',   FALSE, TRUE,  30),
    ('address',         'Address',          'address', FALSE, FALSE, 40),
    ('source_system',   'Source System',    'text',    FALSE, FALSE, 50),
    ('external_id',     'External ID',      'text',    FALSE, FALSE, 60)
) AS attr(key, display_name, data_type, is_required, is_pii, display_order)
ON CONFLICT DO NOTHING;

-- ── Source System Registry ────────────────────────────────────────────────────
-- Registered source systems per tenant with connection metadata

CREATE TABLE IF NOT EXISTS core_mdm.source_systems_registry (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL,
    name                TEXT        NOT NULL,
    code                TEXT        NOT NULL,              -- slug used as source_system tag
    connector_type      TEXT        NOT NULL,              -- salesforce|sap|csv|kafka|rest_api|database|hubspot|custom
    description         TEXT,
    icon                TEXT        DEFAULT '🔌',
    -- Connection config (encrypted at rest via FIELD_ENCRYPTION_KEY)
    connection_config   JSONB       NOT NULL DEFAULT '{}',
    -- Trust/priority for survivorship (1 = highest trust)
    trust_weight        NUMERIC(3,2) NOT NULL DEFAULT 1.0,
    priority            INTEGER     NOT NULL DEFAULT 100,
    -- Entity types this source provides
    entity_types        TEXT[]      NOT NULL DEFAULT '{}',
    -- Sync config
    sync_mode           TEXT        NOT NULL DEFAULT 'manual', -- manual|scheduled|realtime
    sync_schedule       TEXT,                              -- cron expression for scheduled
    last_sync_at        TIMESTAMPTZ,
    last_sync_status    TEXT,                              -- success|failed|running
    last_sync_count     INTEGER,
    -- Status
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    is_connected        BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, code)
);

ALTER TABLE core_mdm.source_systems_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY source_systems_registry_tenant ON core_mdm.source_systems_registry
    USING (tenant_id = current_setting('app.current_tenant', TRUE)::UUID);

CREATE INDEX IF NOT EXISTS idx_source_systems_registry_tenant
    ON core_mdm.source_systems_registry (tenant_id);

-- ── Tenant Admin Users ────────────────────────────────────────────────────────
-- Extends the existing tenant_users concept with invite workflow

CREATE TABLE IF NOT EXISTS platform.tenant_users (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL,
    email           TEXT        NOT NULL,
    full_name       TEXT        NOT NULL DEFAULT '',
    role            TEXT        NOT NULL DEFAULT 'viewer', -- super_admin|admin|steward|analyst|viewer
    invite_token    TEXT,
    invite_expires  TIMESTAMPTZ,
    status          TEXT        NOT NULL DEFAULT 'invited', -- invited|active|suspended
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, email)
);

CREATE INDEX IF NOT EXISTS idx_tenant_users_tenant
    ON platform.tenant_users (tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenant_users_email
    ON platform.tenant_users (email);
CREATE INDEX IF NOT EXISTS idx_tenant_users_invite_token
    ON platform.tenant_users (invite_token)
    WHERE invite_token IS NOT NULL;

-- Trigger to auto-update updated_at on all admin tables
CREATE OR REPLACE FUNCTION core_mdm.touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

DO $$ BEGIN
    CREATE TRIGGER touch_entity_type_configs
        BEFORE UPDATE ON core_mdm.entity_type_configs
        FOR EACH ROW EXECUTE FUNCTION core_mdm.touch_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TRIGGER touch_attribute_schemas
        BEFORE UPDATE ON core_mdm.attribute_schemas
        FOR EACH ROW EXECUTE FUNCTION core_mdm.touch_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TRIGGER touch_source_systems_registry
        BEFORE UPDATE ON core_mdm.source_systems_registry
        FOR EACH ROW EXECUTE FUNCTION core_mdm.touch_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TRIGGER touch_tenant_users
        BEFORE UPDATE ON platform.tenant_users
        FOR EACH ROW EXECUTE FUNCTION core_mdm.touch_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
