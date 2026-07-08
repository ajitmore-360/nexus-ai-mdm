-- ─────────────────────────────────────────────────────────────────────────────
-- 0023: Data Transformation Rules DSL
-- Rules are evaluated in order (priority ASC) when an entity is ingested or
-- updated.  Each rule targets a specific attribute and applies a named
-- transformation with optional parameters.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.transformation_rules (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    rule_name        VARCHAR(255) NOT NULL,
    description      TEXT,
    entity_type      VARCHAR(100),                -- NULL = apply to all entity types
    attribute_name   VARCHAR(255) NOT NULL,        -- attribute key to transform
    -- Transformation function name (see TransformFn enum in Rust)
    transform_fn     VARCHAR(50) NOT NULL CHECK (transform_fn IN (
        'trim',
        'uppercase',
        'lowercase',
        'title_case',
        'normalize_phone',
        'normalize_email',
        'normalize_date',
        'strip_punctuation',
        'extract_digits',
        'regex_replace',
        'map_value',
        'default_if_empty',
        'truncate',
        'pad_left',
        'pad_right',
        'remove_whitespace'
    )),
    -- JSON parameters for the function (e.g., {"pattern":"[^0-9]","replacement":""})
    params           JSONB       NOT NULL DEFAULT '{}',
    -- Execution order within same entity_type + attribute
    priority         SMALLINT    NOT NULL DEFAULT 100,
    is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
    -- Audit
    created_by       UUID,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_transform_rules_type
    ON core_mdm.transformation_rules (tenant_id, entity_type, attribute_name, priority)
    WHERE is_active = true;

ALTER TABLE core_mdm.transformation_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON core_mdm.transformation_rules
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- ─────────────────────────────────────────────────────────────────────────────
-- Transformation execution log — audit trail of what was changed
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS core_mdm.transformation_log (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL,
    entity_id        UUID        NOT NULL,
    rule_id          UUID        NOT NULL REFERENCES core_mdm.transformation_rules(id) ON DELETE CASCADE,
    attribute_name   VARCHAR(255) NOT NULL,
    value_before     TEXT,
    value_after      TEXT,
    applied_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_transform_log_entity
    ON core_mdm.transformation_log (tenant_id, entity_id, applied_at DESC);

ALTER TABLE core_mdm.transformation_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON core_mdm.transformation_log
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- ─────────────────────────────────────────────────────────────────────────────
-- Party Role Management
-- A single entity (person or organization) can hold multiple roles simultaneously:
-- Customer, Supplier, Employee, Partner, etc.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS core_mdm.party_roles (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    entity_id        UUID        NOT NULL REFERENCES core_mdm.entities(id) ON DELETE CASCADE,
    role_code        VARCHAR(50) NOT NULL CHECK (role_code IN (
        'Customer', 'Supplier', 'Employee', 'Partner',
        'Prospect', 'Competitor', 'Regulator', 'Shareholder', 'Other'
    )),
    role_status      VARCHAR(20) NOT NULL DEFAULT 'Active'
                                 CHECK (role_status IN ('Active','Inactive','Suspended')),
    -- Role-specific identifiers (e.g., SAP customer number, vendor code)
    external_id      VARCHAR(255),
    source_system    VARCHAR(100),
    -- Validity period
    valid_from       DATE,
    valid_to         DATE,
    metadata         JSONB       NOT NULL DEFAULT '{}',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_party_role UNIQUE (tenant_id, entity_id, role_code)
);

CREATE INDEX IF NOT EXISTS idx_party_roles_entity
    ON core_mdm.party_roles (tenant_id, entity_id);

CREATE INDEX IF NOT EXISTS idx_party_roles_code
    ON core_mdm.party_roles (tenant_id, role_code, role_status);

ALTER TABLE core_mdm.party_roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON core_mdm.party_roles
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);
