-- Migration: 002008_create_entity_relationships.sql
-- Description: Cross-domain entity relationship tables (Reltio-style MDM)
-- Schema: core_mdm

-- ---------------------------------------------------------------------------
-- Table 1: core_mdm.relationship_types
-- Registry of named relationship types per tenant
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core_mdm.relationship_types (
    type_id             UUID        NOT NULL DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL,
    name                TEXT        NOT NULL,
    display_name        TEXT        NOT NULL,
    from_entity_type    TEXT        NOT NULL,
    to_entity_type      TEXT        NOT NULL,
    is_bidirectional    BOOLEAN     NOT NULL DEFAULT FALSE,
    description         TEXT,
    is_system           BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT relationship_types_pkey
        PRIMARY KEY (type_id),

    CONSTRAINT relationship_types_tenant_fk
        FOREIGN KEY (tenant_id)
        REFERENCES core_mdm.tenants (tenant_id)
        ON DELETE CASCADE,

    CONSTRAINT relationship_types_tenant_name_unique
        UNIQUE (tenant_id, name)
);

-- ---------------------------------------------------------------------------
-- Table 2: core_mdm.entity_relationships
-- Actual relationship instances between entity records
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core_mdm.entity_relationships (
    relationship_id     UUID            NOT NULL DEFAULT gen_random_uuid(),
    tenant_id           UUID            NOT NULL,
    type_id             UUID            NOT NULL,
    from_entity_id      UUID            NOT NULL,
    to_entity_id        UUID            NOT NULL,
    strength            NUMERIC(5, 4)   NOT NULL DEFAULT 1.0,
    attributes          JSONB           NOT NULL DEFAULT '{}',
    created_by          UUID,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT entity_relationships_pkey
        PRIMARY KEY (relationship_id),

    CONSTRAINT entity_relationships_tenant_fk
        FOREIGN KEY (tenant_id)
        REFERENCES core_mdm.tenants (tenant_id)
        ON DELETE CASCADE,

    CONSTRAINT entity_relationships_type_fk
        FOREIGN KEY (type_id)
        REFERENCES core_mdm.relationship_types (type_id)
        ON DELETE CASCADE,

    CONSTRAINT entity_relationships_unique
        UNIQUE (tenant_id, type_id, from_entity_id, to_entity_id)
);

-- ---------------------------------------------------------------------------
-- Indexes: core_mdm.relationship_types
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_relationship_types_tenant_id
    ON core_mdm.relationship_types (tenant_id);

-- ---------------------------------------------------------------------------
-- Indexes: core_mdm.entity_relationships
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_entity_relationships_tenant_id
    ON core_mdm.entity_relationships (tenant_id);

CREATE INDEX IF NOT EXISTS idx_entity_relationships_tenant_from
    ON core_mdm.entity_relationships (tenant_id, from_entity_id);

CREATE INDEX IF NOT EXISTS idx_entity_relationships_tenant_to
    ON core_mdm.entity_relationships (tenant_id, to_entity_id);

CREATE INDEX IF NOT EXISTS idx_entity_relationships_type_id
    ON core_mdm.entity_relationships (type_id);

-- ---------------------------------------------------------------------------
-- Seed: 8 system relationship types
-- System tenant: 00000000-0000-0000-0000-000000000001
-- ---------------------------------------------------------------------------
INSERT INTO core_mdm.relationship_types
    (type_id, tenant_id, name, display_name, from_entity_type, to_entity_type, is_bidirectional, description, is_system)
VALUES
    (
        '10000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001',
        'supplied_by',
        'Supplied By',
        'PRODUCT',
        'SUPPLIER',
        FALSE,
        'Links a product to the supplier that provides it.',
        TRUE
    ),
    (
        '10000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000001',
        'purchased_by',
        'Purchased By',
        'PRODUCT',
        'CUSTOMER',
        FALSE,
        'Links a product to a customer that purchases it.',
        TRUE
    ),
    (
        '10000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-000000000001',
        'employed_by',
        'Employed By',
        'EMPLOYEE',
        'ORGANIZATION',
        FALSE,
        'Links an employee to the organization that employs them.',
        TRUE
    ),
    (
        '10000000-0000-0000-0000-000000000004',
        '00000000-0000-0000-0000-000000000001',
        'located_at',
        'Located At',
        'CUSTOMER',
        'LOCATION',
        FALSE,
        'Links a customer to their physical or billing location.',
        TRUE
    ),
    (
        '10000000-0000-0000-0000-000000000005',
        '00000000-0000-0000-0000-000000000001',
        'subsidiary_of',
        'Subsidiary Of',
        'ORGANIZATION',
        'ORGANIZATION',
        FALSE,
        'Links a subsidiary organization to its parent organization.',
        TRUE
    ),
    (
        '10000000-0000-0000-0000-000000000006',
        '00000000-0000-0000-0000-000000000001',
        'part_of',
        'Part Of',
        'PRODUCT',
        'PRODUCT',
        FALSE,
        'Links a component product to the parent product it belongs to (component hierarchy).',
        TRUE
    ),
    (
        '10000000-0000-0000-0000-000000000007',
        '00000000-0000-0000-0000-000000000001',
        'managed_by',
        'Managed By',
        'ASSET',
        'EMPLOYEE',
        FALSE,
        'Links an asset to the employee responsible for managing it.',
        TRUE
    ),
    (
        '10000000-0000-0000-0000-000000000008',
        '00000000-0000-0000-0000-000000000001',
        'billed_to',
        'Billed To',
        'PRODUCT',
        'CUSTOMER',
        FALSE,
        'Links a product to the customer it is billed to.',
        TRUE
    )
ON CONFLICT DO NOTHING;
