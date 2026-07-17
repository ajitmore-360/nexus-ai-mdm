-- =============================================================================
-- Migration 002025: Schema divergence resolution
-- Resolves conflicts between the two migration streams (000001-002024 and 0001-0025),
-- removes the dangerous vector_embedding column, drops the dead golden_attributes
-- table, and fixes the cleanup_old_events bug where it referenced the wrong column.
-- =============================================================================

-- ── 1. entity_attributes: attribute_name → attribute_key ─────────────────────
-- Migration 000008 used attribute_name; all Rust code uses attribute_key.
DO $$ BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'core_mdm'
          AND table_name   = 'entity_attributes'
          AND column_name  = 'attribute_name'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'core_mdm'
          AND table_name   = 'entity_attributes'
          AND column_name  = 'attribute_key'
    ) THEN
        ALTER TABLE core_mdm.entity_attributes
            RENAME COLUMN attribute_name TO attribute_key;
    END IF;
END $$;

-- ── 2. Drop vector_embedding — 1536-dim floats at 385M rows = 2.36 TB ────────
ALTER TABLE core_mdm.entity_attributes
    DROP COLUMN IF EXISTS vector_embedding;

-- ── 3. Add columns that 000008 was missing but Rust code expects ──────────────
ALTER TABLE core_mdm.entity_attributes
    ADD COLUMN IF NOT EXISTS data_type TEXT    NOT NULL DEFAULT 'string',
    ADD COLUMN IF NOT EXISTS is_masked BOOLEAN NOT NULL DEFAULT FALSE;

-- confidence_score (000008 name) → confidence (Rust / 0003 name)
DO $$ BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'core_mdm'
          AND table_name   = 'entity_attributes'
          AND column_name  = 'confidence_score'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'core_mdm'
          AND table_name   = 'entity_attributes'
          AND column_name  = 'confidence'
    ) THEN
        ALTER TABLE core_mdm.entity_attributes
            RENAME COLUMN confidence_score TO confidence;
    ELSIF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'core_mdm'
          AND table_name   = 'entity_attributes'
          AND column_name  = 'confidence'
    ) THEN
        ALTER TABLE core_mdm.entity_attributes
            ADD COLUMN confidence FLOAT4;
    END IF;
END $$;

-- ── 4. Drop dead golden_attributes table ─────────────────────────────────────
-- Rust only ever writes to golden_record_attributes (000010).
-- This slim duplicate table (0003) is never read or written by any service.
DROP TABLE IF EXISTS core_mdm.golden_attributes;

-- ── 5. Fix cleanup_old_events: column is failed_at, not created_at ────────────
CREATE OR REPLACE FUNCTION event_store.cleanup_old_events(
    retention_hours INT DEFAULT 720
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    deleted BIGINT;
BEGIN
    DELETE FROM event_store.dead_letter_events
    WHERE failed_at < NOW() - (retention_hours || ' hours')::INTERVAL;
    GET DIAGNOSTICS deleted = ROW_COUNT;
    RETURN deleted;
END;
$$;
