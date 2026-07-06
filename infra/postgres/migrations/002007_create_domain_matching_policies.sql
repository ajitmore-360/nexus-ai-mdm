-- Migration: 002007_create_domain_matching_policies.sql
-- Purpose: Per-entity-type matching policy overrides for specific domains
--          (Customer, Product, Supplier, etc.), superseding the global MatchingPolicy.
-- Schema:  core_mdm (pre-existing)

-- ---------------------------------------------------------------------------
-- Table: core_mdm.domain_matching_policies
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core_mdm.domain_matching_policies (
    -- Primary key
    policy_id               UUID            NOT NULL DEFAULT gen_random_uuid(),

    -- Tenant isolation
    tenant_id               UUID            NOT NULL,

    -- Domain discriminator (e.g. 'Customer', 'Product', 'Supplier')
    entity_type_code        TEXT            NOT NULL,

    -- -----------------------------------------------------------------------
    -- Matching thresholds  (MatchingPolicy fields → NUMERIC(5,4))
    -- -----------------------------------------------------------------------
    auto_merge_threshold    NUMERIC(5,4)    NOT NULL DEFAULT 0.9500,
    review_threshold        NUMERIC(5,4)    NOT NULL DEFAULT 0.7500,
    ambiguity_delta         NUMERIC(5,4)    NOT NULL DEFAULT 0.0300,

    -- -----------------------------------------------------------------------
    -- Algorithm weights for individual match components
    -- -----------------------------------------------------------------------
    exact_weight            NUMERIC(5,4)    NOT NULL DEFAULT 0.3500,
    fuzzy_weight            NUMERIC(5,4)    NOT NULL DEFAULT 0.3000,
    phonetic_weight         NUMERIC(5,4)    NOT NULL DEFAULT 0.1000,
    semantic_weight         NUMERIC(5,4)    NOT NULL DEFAULT 0.1500,
    vector_weight           NUMERIC(5,4)    NOT NULL DEFAULT 0.1000,

    -- -----------------------------------------------------------------------
    -- Master-record scoring weights
    -- -----------------------------------------------------------------------
    master_weight_score       NUMERIC(5,4)  NOT NULL DEFAULT 0.5000,
    master_weight_confidence  NUMERIC(5,4)  NOT NULL DEFAULT 0.3000,
    master_weight_centrality  NUMERIC(5,4)  NOT NULL DEFAULT 0.2000,

    -- -----------------------------------------------------------------------
    -- Cluster cap  (MatchingPolicy.max_clusters: usize → INT)
    -- -----------------------------------------------------------------------
    max_clusters            INT             NOT NULL DEFAULT 100,

    -- -----------------------------------------------------------------------
    -- Administrative / audit columns
    -- -----------------------------------------------------------------------
    description             TEXT,
    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- -----------------------------------------------------------------------
    -- Constraints
    -- -----------------------------------------------------------------------
    CONSTRAINT domain_matching_policies_pkey
        PRIMARY KEY (policy_id),

    CONSTRAINT domain_matching_policies_tenant_fk
        FOREIGN KEY (tenant_id)
        REFERENCES core_mdm.tenants (tenant_id)
        ON DELETE CASCADE,

    CONSTRAINT domain_matching_policies_tenant_entity_type_uq
        UNIQUE (tenant_id, entity_type_code),

    -- Threshold sanity: all weight/threshold values must be in [0, 1]
    CONSTRAINT domain_matching_policies_auto_merge_threshold_range
        CHECK (auto_merge_threshold BETWEEN 0.0000 AND 1.0000),
    CONSTRAINT domain_matching_policies_review_threshold_range
        CHECK (review_threshold BETWEEN 0.0000 AND 1.0000),
    CONSTRAINT domain_matching_policies_ambiguity_delta_range
        CHECK (ambiguity_delta BETWEEN 0.0000 AND 1.0000),
    CONSTRAINT domain_matching_policies_exact_weight_range
        CHECK (exact_weight BETWEEN 0.0000 AND 1.0000),
    CONSTRAINT domain_matching_policies_fuzzy_weight_range
        CHECK (fuzzy_weight BETWEEN 0.0000 AND 1.0000),
    CONSTRAINT domain_matching_policies_phonetic_weight_range
        CHECK (phonetic_weight BETWEEN 0.0000 AND 1.0000),
    CONSTRAINT domain_matching_policies_semantic_weight_range
        CHECK (semantic_weight BETWEEN 0.0000 AND 1.0000),
    CONSTRAINT domain_matching_policies_vector_weight_range
        CHECK (vector_weight BETWEEN 0.0000 AND 1.0000),
    CONSTRAINT domain_matching_policies_master_weight_score_range
        CHECK (master_weight_score BETWEEN 0.0000 AND 1.0000),
    CONSTRAINT domain_matching_policies_master_weight_confidence_range
        CHECK (master_weight_confidence BETWEEN 0.0000 AND 1.0000),
    CONSTRAINT domain_matching_policies_master_weight_centrality_range
        CHECK (master_weight_centrality BETWEEN 0.0000 AND 1.0000),

    -- max_clusters must be a positive integer
    CONSTRAINT domain_matching_policies_max_clusters_positive
        CHECK (max_clusters > 0),

    -- review_threshold must be strictly below auto_merge_threshold
    CONSTRAINT domain_matching_policies_threshold_ordering
        CHECK (review_threshold < auto_merge_threshold)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS domain_matching_policies_tenant_id_idx
    ON core_mdm.domain_matching_policies (tenant_id);

CREATE INDEX IF NOT EXISTS domain_matching_policies_tenant_entity_type_idx
    ON core_mdm.domain_matching_policies (tenant_id, entity_type_code);

-- ---------------------------------------------------------------------------
-- Auto-update updated_at on row modification
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core_mdm.set_domain_matching_policies_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS domain_matching_policies_updated_at_trg
    ON core_mdm.domain_matching_policies;

CREATE TRIGGER domain_matching_policies_updated_at_trg
    BEFORE UPDATE ON core_mdm.domain_matching_policies
    FOR EACH ROW
    EXECUTE FUNCTION core_mdm.set_domain_matching_policies_updated_at();

-- ---------------------------------------------------------------------------
-- Comments
-- ---------------------------------------------------------------------------
COMMENT ON TABLE core_mdm.domain_matching_policies IS
    'Per-entity-type matching policy overrides. A row here supersedes the '
    'global MatchingPolicy for a specific (tenant, entity_type_code) pair, '
    'allowing different merge thresholds and algorithm weights for domains '
    'such as Customer, Product, and Supplier.';

COMMENT ON COLUMN core_mdm.domain_matching_policies.policy_id             IS 'Surrogate primary key (UUID v4).';
COMMENT ON COLUMN core_mdm.domain_matching_policies.tenant_id             IS 'Owning tenant; cascades deletes.';
COMMENT ON COLUMN core_mdm.domain_matching_policies.entity_type_code      IS 'Domain discriminator, e.g. ''Customer'', ''Product'', ''Supplier''.';
COMMENT ON COLUMN core_mdm.domain_matching_policies.auto_merge_threshold  IS 'Score >= this → automatic merge (default 0.95, mirrors MatchingPolicy.auto_merge_threshold).';
COMMENT ON COLUMN core_mdm.domain_matching_policies.review_threshold      IS 'Score >= this → human review queue (default 0.75, mirrors MatchingPolicy.review_threshold).';
COMMENT ON COLUMN core_mdm.domain_matching_policies.ambiguity_delta       IS 'Minimum spread between top candidates before flagging as ambiguous (default 0.03).';
COMMENT ON COLUMN core_mdm.domain_matching_policies.exact_weight          IS 'Weight for exact-string matching component (default 0.35).';
COMMENT ON COLUMN core_mdm.domain_matching_policies.fuzzy_weight          IS 'Weight for fuzzy / edit-distance matching component (default 0.30).';
COMMENT ON COLUMN core_mdm.domain_matching_policies.phonetic_weight       IS 'Weight for phonetic (Soundex/Metaphone) matching component (default 0.10).';
COMMENT ON COLUMN core_mdm.domain_matching_policies.semantic_weight       IS 'Weight for semantic / NLP matching component (default 0.15).';
COMMENT ON COLUMN core_mdm.domain_matching_policies.vector_weight         IS 'Weight for embedding-vector similarity component (default 0.10).';
COMMENT ON COLUMN core_mdm.domain_matching_policies.master_weight_score   IS 'Weight applied to match score when electing a master record (default 0.50).';
COMMENT ON COLUMN core_mdm.domain_matching_policies.master_weight_confidence IS 'Weight applied to confidence when electing a master record (default 0.30).';
COMMENT ON COLUMN core_mdm.domain_matching_policies.master_weight_centrality IS 'Weight applied to graph centrality when electing a master record (default 0.20).';
COMMENT ON COLUMN core_mdm.domain_matching_policies.max_clusters          IS 'Maximum number of match clusters to produce per run (default 100).';
COMMENT ON COLUMN core_mdm.domain_matching_policies.description           IS 'Optional human-readable description of this policy override.';
COMMENT ON COLUMN core_mdm.domain_matching_policies.is_active             IS 'When FALSE the policy is ignored and the global default is used instead.';
COMMENT ON COLUMN core_mdm.domain_matching_policies.created_at            IS 'Row creation timestamp (UTC).';
COMMENT ON COLUMN core_mdm.domain_matching_policies.updated_at            IS 'Row last-modified timestamp (UTC), maintained by trigger.';
