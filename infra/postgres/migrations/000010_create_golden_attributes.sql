--
-- ============================================
-- GOLDEN ATTRIBUTES TABLE
-- ============================================
--

--CREATE TABLE IF NOT EXISTS core_mdm.golden_attributes (
CREATE TABLE IF NOT EXISTS core_mdm.golden_record_attributes (
    --
    -- Primary identity
    --

    golden_attribute_id UUID PRIMARY KEY,

    tenant_id UUID NOT NULL,

    golden_record_id UUID NOT NULL,

    --
    -- Attribute identity
    --

    attribute_id UUID NOT NULL,

    attribute_key VARCHAR(255) NOT NULL,

    attribute_type VARCHAR(255),

    semantic_type VARCHAR(255),

    --
    -- Attribute payload
    --

    attribute_value JSONB NOT NULL,

    normalized_value JSONB,

    searchable_value TEXT,

    --
    -- Source lineage
    --

    selected_from_entity UUID NOT NULL,

    selected_from_source VARCHAR(255),

    source_attribute_id UUID,

    candidate_entities JSONB NOT NULL DEFAULT '[]'::jsonb,

    --
    -- Survivorship
    --

    survivorship_rule_id UUID,

    survivorship_execution_id UUID,

    survivorship_strategy VARCHAR(255),

    survivorship_score DOUBLE PRECISION,

    confidence_score DOUBLE PRECISION,

    ai_confidence DOUBLE PRECISION,

    explainability TEXT,

    --
    -- Human governance
    --

    overridden_by_user UUID,

    overridden_at TIMESTAMPTZ,

    override_reason TEXT,

    approved BOOLEAN NOT NULL DEFAULT FALSE,

    approved_by UUID,

    approved_at TIMESTAMPTZ,

    --
    -- Search + indexing
    --

    searchable BOOLEAN NOT NULL DEFAULT TRUE,

    indexed BOOLEAN NOT NULL DEFAULT TRUE,

    encrypted BOOLEAN NOT NULL DEFAULT FALSE,

    vector_enabled BOOLEAN NOT NULL DEFAULT FALSE,

    embedding_reference VARCHAR(1024),

    --
    -- Policy + governance
    --

    policy_refs JSONB NOT NULL DEFAULT '[]'::jsonb,

    tags JSONB NOT NULL DEFAULT '[]'::jsonb,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    --
    -- Versioning
    --

    attribute_version BIGINT NOT NULL DEFAULT 1,

    is_current BOOLEAN NOT NULL DEFAULT TRUE,

    valid_from TIMESTAMPTZ,

    valid_to TIMESTAMPTZ,

    --
    -- Audit
    --

    created_by UUID,

    updated_by UUID,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    --
    -- Constraints
    --

    CONSTRAINT fk_golden_record_attributes_record
        FOREIGN KEY (golden_record_id)
        REFERENCES core_mdm.golden_records(golden_record_id)
        ON DELETE CASCADE
);

--
-- ============================================
-- INDEXES
-- ============================================
--

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_tenant
ON core_mdm.golden_record_attributes(tenant_id);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_record
ON core_mdm.golden_record_attributes(golden_record_id);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_attribute_id
ON core_mdm.golden_record_attributes(attribute_id);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_key
ON core_mdm.golden_record_attributes(attribute_key);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_type
ON core_mdm.golden_record_attributes(attribute_type);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_semantic
ON core_mdm.golden_record_attributes(semantic_type);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_source_entity
ON core_mdm.golden_record_attributes(selected_from_entity);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_source_system
ON core_mdm.golden_record_attributes(selected_from_source);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_rule
ON core_mdm.golden_record_attributes(survivorship_rule_id);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_execution
ON core_mdm.golden_record_attributes(survivorship_execution_id);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_current
ON core_mdm.golden_record_attributes(is_current);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_validity
ON core_mdm.golden_record_attributes(
    valid_from,
    valid_to
);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_created
ON core_mdm.golden_record_attributes(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_updated
ON core_mdm.golden_record_attributes(updated_at DESC);

--
-- ============================================
-- SEARCH INDEXES
-- ============================================
--

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_searchable
ON core_mdm.golden_record_attributes(searchable_value);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_value_gin
ON core_mdm.golden_record_attributes
USING GIN(attribute_value);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_normalized_gin
ON core_mdm.golden_record_attributes
USING GIN(normalized_value);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_candidate_entities
ON core_mdm.golden_record_attributes
USING GIN(candidate_entities);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_policy_refs
ON core_mdm.golden_record_attributes
USING GIN(policy_refs);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_tags
ON core_mdm.golden_record_attributes
USING GIN(tags);

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_metadata
ON core_mdm.golden_record_attributes
USING GIN(metadata);

--
-- ============================================
-- PARTIAL INDEXES
-- ============================================
--

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_active
ON core_mdm.golden_record_attributes(
    tenant_id,
    golden_record_id
)
WHERE is_current = TRUE;

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_vector_enabled
ON core_mdm.golden_record_attributes(vector_enabled)
WHERE vector_enabled = TRUE;

CREATE INDEX IF NOT EXISTS idx_golden_record_attributes_approved
ON core_mdm.golden_record_attributes(approved)
WHERE approved = TRUE;

--
-- ============================================
-- UPDATED_AT TRIGGER
-- ============================================
--

CREATE OR REPLACE FUNCTION core_mdm.set_golden_record_attributes_updated_at()
RETURNS TRIGGER
AS $$
BEGIN

    NEW.updated_at = NOW();

    RETURN NEW;
END;

$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_golden_record_attributes_updated_at
ON core_mdm.golden_record_attributes;

CREATE TRIGGER trg_golden_record_attributes_updated_at
BEFORE UPDATE
ON core_mdm.golden_record_attributes
FOR EACH ROW
EXECUTE FUNCTION core_mdm.set_golden_record_attributes_updated_at();

--
-- ============================================
-- COMMENTS
-- ============================================
--

COMMENT ON TABLE core_mdm.golden_record_attributes
IS 'Mastered survivorship-selected attributes for golden records';

COMMENT ON COLUMN core_mdm.golden_record_attributes.attribute_value
IS 'Canonical mastered attribute value';

COMMENT ON COLUMN core_mdm.golden_record_attributes.selected_from_entity
IS 'Source entity selected during survivorship';

COMMENT ON COLUMN core_mdm.golden_record_attributes.survivorship_strategy
IS 'Applied survivorship strategy';

COMMENT ON COLUMN core_mdm.golden_record_attributes.explainability
IS 'Human/AI explainability summary';

COMMENT ON COLUMN core_mdm.golden_record_attributes.vector_enabled
IS 'Whether attribute participates in vector search';

COMMENT ON COLUMN core_mdm.golden_record_attributes.embedding_reference
IS 'Reference to embedding/vector storage';

COMMENT ON COLUMN core_mdm.golden_record_attributes.policy_refs
IS 'Governance and policy evaluation references';

COMMENT ON COLUMN core_mdm.golden_record_attributes.candidate_entities
IS 'All candidate entities considered during survivorship';