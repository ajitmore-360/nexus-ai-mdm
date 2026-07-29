-- =============================================================================
-- Migration 002028: Add current_attributes JSONB to entities and golden_records
--
-- current_attributes is a denormalised hot-document cache that collapses the
-- entity's attribute rows into a single JSONB column on the entities row.
--
-- Benefits:
--   • Single-entity profile fetch: from an N-row EAV join + pivot to one row read
--   • FTS ranking: eliminates the correlated subquery in searcher.rs (from O(N)
--     per result row to O(1) column read)
--   • The GIN index on to_tsvector(current_attributes::text) makes full-text
--     search over attributes an index scan rather than a sequential EAV scan
--
-- Updated by: entity_repository.rs on INSERT (built from attribute loop),
--             entity_repository.rs on attribute UPDATE (re-aggregated via SQL),
--             survivorship/engine.rs when writing a golden record.
-- =============================================================================

-- ── 1. entities ───────────────────────────────────────────────────────────────
ALTER TABLE core_mdm.entities
    ADD COLUMN IF NOT EXISTS current_attributes JSONB NOT NULL DEFAULT '{}';

-- Backfill from entity_attributes for rows that already exist
UPDATE core_mdm.entities e
SET current_attributes = agg.attrs
FROM (
    SELECT
        entity_id,
        jsonb_object_agg(attribute_key, attribute_value) AS attrs
    FROM core_mdm.entity_attributes
    GROUP BY entity_id
) agg
WHERE agg.entity_id = e.entity_id;

-- GIN index for FTS — the search-service FTS query uses this instead of the
-- correlated subquery that fired once per result entity.
CREATE INDEX IF NOT EXISTS idx_entities_current_attrs_fts
    ON core_mdm.entities
    USING GIN (to_tsvector('english', current_attributes::text))
    WHERE valid_to = 'infinity';

-- GIN for JSONB path / containment queries (API filter by attribute value)
CREATE INDEX IF NOT EXISTS idx_entities_current_attrs_gin
    ON core_mdm.entities
    USING GIN (current_attributes jsonb_path_ops)
    WHERE valid_to = 'infinity';

-- ── 2. golden_records ─────────────────────────────────────────────────────────
ALTER TABLE core_mdm.golden_records
    ADD COLUMN IF NOT EXISTS current_attributes JSONB NOT NULL DEFAULT '{}';

-- Backfill from golden_record_attributes (is_current rows only)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'core_mdm'
          AND table_name   = 'golden_record_attributes'
          AND column_name  = 'is_current'
    ) THEN
        UPDATE core_mdm.golden_records gr
        SET current_attributes = agg.attrs
        FROM (
            SELECT
                golden_record_id,
                jsonb_object_agg(attribute_key, attribute_value) AS attrs
            FROM core_mdm.golden_record_attributes
            WHERE is_current = TRUE
            GROUP BY golden_record_id
        ) agg
        WHERE agg.golden_record_id = gr.golden_record_id;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_golden_records_current_attrs_fts
    ON core_mdm.golden_records
    USING GIN (to_tsvector('english', current_attributes::text))
    WHERE valid_to = 'infinity';
