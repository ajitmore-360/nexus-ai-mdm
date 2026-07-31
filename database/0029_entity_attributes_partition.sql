-- =============================================================================
-- Migration 002027: Convert entity_attributes to LIST-partitioned table
--
-- At target scale (2-3M customers, 2-3M vendors, 5-10M materials with 30 attrs
-- each = 385M attribute rows, ~130 GB):
--
--   Customer  partition ≈  67M rows   ~23 GB
--   Vendor    partition ≈  55M rows   ~19 GB
--   Material  partition ≈ 263M rows   ~89 GB
--
-- A query filtered by entity_type now scans ONE partition instead of the full
-- 385M-row table — 5-6× reduction in I/O for cross-entity searches; effectively
-- instant for indexed single-entity lookups (already fast, remains fast).
--
-- NOTE: PostgreSQL requires the PRIMARY KEY of a partitioned table to include
-- all partition columns. PK becomes (attribute_id, entity_type) — attribute_id
-- is a UUID so the pair is still globally unique.
--
-- This migration is ONLINE-SAFE for empty / small dev databases. For a live
-- production database with existing rows, schedule during a low-traffic window
-- as the INSERT INTO ... SELECT copies all rows.
-- =============================================================================

BEGIN;

-- ── Step 1: Rename flat table to a backup name ────────────────────────────────
ALTER TABLE core_mdm.entity_attributes
    RENAME TO entity_attributes_unpartitioned;

-- Drop indexes that were on the old table — they don't transfer, and we'll
-- create equivalent ones on the new partitioned parent below.
DROP INDEX IF EXISTS core_mdm.idx_ea_type_key_val_text;
DROP INDEX IF EXISTS core_mdm.idx_ea_names_text;
DROP INDEX IF EXISTS core_mdm.idx_ea_entity_type;

-- ── Step 2: Create the partitioned parent table ───────────────────────────────
CREATE TABLE core_mdm.entity_attributes (
    attribute_id          UUID        NOT NULL DEFAULT gen_random_uuid(),
    tenant_id             UUID        NOT NULL,
    entity_id             UUID        NOT NULL,
    entity_type           TEXT        NOT NULL,
    attribute_key         TEXT        NOT NULL,
    attribute_value       JSONB       NOT NULL,
    attribute_value_text  TEXT        GENERATED ALWAYS AS (attribute_value #>> '{}') STORED,
    data_type             TEXT        NOT NULL DEFAULT 'string',
    confidence            FLOAT4,
    source_system         TEXT,
    is_masked             BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (attribute_id, entity_type),

    CONSTRAINT fk_ea_entity
        FOREIGN KEY (entity_id)
        REFERENCES core_mdm.entities(entity_id)
        ON DELETE CASCADE
) PARTITION BY LIST (entity_type);

-- ── Step 3: Named partitions for the three dominant types ─────────────────────
CREATE TABLE core_mdm.entity_attributes_customer
    PARTITION OF core_mdm.entity_attributes
    FOR VALUES IN ('Customer');

CREATE TABLE core_mdm.entity_attributes_vendor
    PARTITION OF core_mdm.entity_attributes
    FOR VALUES IN ('Vendor');

CREATE TABLE core_mdm.entity_attributes_material
    PARTITION OF core_mdm.entity_attributes
    FOR VALUES IN ('Material');

-- Named partitions for known secondary types (keeps them out of the default
-- catch-all bucket and allows targeted autovacuum / fillfactor tuning later)
CREATE TABLE core_mdm.entity_attributes_product
    PARTITION OF core_mdm.entity_attributes
    FOR VALUES IN ('Product');

CREATE TABLE core_mdm.entity_attributes_employee
    PARTITION OF core_mdm.entity_attributes
    FOR VALUES IN ('Employee');

CREATE TABLE core_mdm.entity_attributes_account
    PARTITION OF core_mdm.entity_attributes
    FOR VALUES IN ('Account');

CREATE TABLE core_mdm.entity_attributes_location
    PARTITION OF core_mdm.entity_attributes
    FOR VALUES IN ('Location');

CREATE TABLE core_mdm.entity_attributes_organization
    PARTITION OF core_mdm.entity_attributes
    FOR VALUES IN ('Organization');

CREATE TABLE core_mdm.entity_attributes_asset
    PARTITION OF core_mdm.entity_attributes
    FOR VALUES IN ('Asset');

CREATE TABLE core_mdm.entity_attributes_refdata
    PARTITION OF core_mdm.entity_attributes
    FOR VALUES IN ('ReferenceData');

-- Catch-all for Custom(…) entity types added at runtime by tenant config
CREATE TABLE core_mdm.entity_attributes_other
    PARTITION OF core_mdm.entity_attributes
    DEFAULT;

-- ── Step 4: Indexes on partitioned parent (propagate to all partitions) ────────
-- Single-entity attribute fetch (primary access pattern)
CREATE INDEX idx_ea_entity_lookup
    ON core_mdm.entity_attributes (tenant_id, entity_id);

-- Matching blocking-key exact lookup — uses generated text column
CREATE INDEX idx_ea_key_text
    ON core_mdm.entity_attributes (tenant_id, entity_type, attribute_key, attribute_value_text);

-- Autocomplete / display-name prefix search (high-frequency, small result set)
CREATE INDEX idx_ea_names_text
    ON core_mdm.entity_attributes (tenant_id, lower(attribute_value_text))
    WHERE attribute_key IN (
        'name', 'full_name', 'legal_name', 'company_name',
        'business_name', 'display_name', 'organization_name',
        'organisation_name', 'customer_name', 'vendor_name',
        'product_name', 'title'
    );

-- GIN kept only for complex JSONB (arrays, nested objects); scalars served by text index
CREATE INDEX idx_ea_value_gin
    ON core_mdm.entity_attributes USING GIN (attribute_value jsonb_path_ops)
    WHERE data_type NOT IN ('string', 'number', 'boolean', 'date');

-- ── Step 5: Copy existing rows into the partitioned table ─────────────────────
INSERT INTO core_mdm.entity_attributes (
    attribute_id,
    tenant_id,
    entity_id,
    entity_type,
    attribute_key,
    attribute_value,
    data_type,
    confidence,
    source_system,
    is_masked,
    created_at
)
SELECT
    attribute_id,
    tenant_id,
    entity_id,
    COALESCE(entity_type, 'Unknown'),
    COALESCE(attribute_key, 'unknown'),
    attribute_value,
    COALESCE(data_type, 'string'),
    confidence,
    source_system,
    COALESCE(is_masked, FALSE),
    created_at
FROM core_mdm.entity_attributes_unpartitioned;

-- ── Step 6: Drop unpartitioned backup ─────────────────────────────────────────
DROP TABLE core_mdm.entity_attributes_unpartitioned;

-- ── Step 7: Row-level security (inherited by all partitions) ──────────────────
ALTER TABLE core_mdm.entity_attributes ENABLE ROW LEVEL SECURITY;

CREATE POLICY ea_tenant_isolation
    ON core_mdm.entity_attributes
    USING (tenant_id = current_setting('app.current_tenant', TRUE)::uuid);

COMMIT;
