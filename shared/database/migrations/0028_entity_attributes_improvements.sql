-- =============================================================================
-- Migration 002026: entity_attributes — add entity_type + generated text column
--
-- entity_type:          required for LIST partitioning in 002027 and for
--                       pruning partition scans in matching and search queries.
-- attribute_value_text: STORED GENERATED column — scalar text extracted from
--                       the JSONB attribute_value automatically by PostgreSQL.
--                       Replaces the fragile trim(both '"' from ::text) cast
--                       used in matching_repository, and the #>> '{}' used in
--                       autocomplete. Being B-tree indexable it is far cheaper
--                       than a GIN index on JSONB for scalar equality/LIKE ops.
-- =============================================================================

-- ── 1. Add entity_type (backfill, then NOT NULL) ──────────────────────────────
ALTER TABLE core_mdm.entity_attributes
    ADD COLUMN IF NOT EXISTS entity_type TEXT;

UPDATE core_mdm.entity_attributes ea
SET    entity_type = e.entity_type
FROM   core_mdm.entities e
WHERE  e.entity_id   = ea.entity_id
  AND  ea.entity_type IS NULL;

UPDATE core_mdm.entity_attributes
SET    entity_type = 'Unknown'
WHERE  entity_type IS NULL;

ALTER TABLE core_mdm.entity_attributes
    ALTER COLUMN entity_type SET NOT NULL;

-- ── 2. STORED generated column — auto-extracts scalar JSONB value as text ─────
ALTER TABLE core_mdm.entity_attributes
    ADD COLUMN IF NOT EXISTS attribute_value_text TEXT
    GENERATED ALWAYS AS (attribute_value #>> '{}') STORED;

-- ── 3. Composite B-tree covering index for matching blocking-key lookup ────────
-- (tenant_id, entity_type) prunes to the right partition after 002027;
-- (attribute_key, attribute_value_text) gives the exact-match join O(log N).
CREATE INDEX IF NOT EXISTS idx_ea_type_key_val_text
    ON core_mdm.entity_attributes (tenant_id, entity_type, attribute_key, attribute_value_text);

-- ── 4. Partial index for autocomplete / display-name prefix search ─────────────
CREATE INDEX IF NOT EXISTS idx_ea_names_text
    ON core_mdm.entity_attributes (tenant_id, lower(attribute_value_text))
    WHERE attribute_key IN (
        'name', 'full_name', 'legal_name', 'company_name',
        'business_name', 'display_name', 'organization_name',
        'organisation_name', 'customer_name', 'vendor_name',
        'product_name', 'title'
    );

-- ── 5. entity_type bare index for cross-type aggregation queries ───────────────
CREATE INDEX IF NOT EXISTS idx_ea_entity_type
    ON core_mdm.entity_attributes (entity_type, tenant_id);
