--
-- ============================================
-- MATCHING TABLES
-- ============================================
--

CREATE TABLE IF NOT EXISTS core_mdm.match_requests (

    --
    -- Identity
    --

    request_id UUID PRIMARY KEY,

    tenant_id UUID NOT NULL,

    correlation_id UUID,

    --
    -- Entity context
    --

    entity_type VARCHAR(255) NOT NULL,

    source_entity_id UUID,

    canonical_entity_id UUID,

    --
    -- Matching configuration
    --

    strategy VARCHAR(255) NOT NULL,

    threshold DOUBLE PRECISION,

    ai_assisted BOOLEAN NOT NULL DEFAULT FALSE,

    semantic_matching BOOLEAN NOT NULL DEFAULT FALSE,

    graph_matching BOOLEAN NOT NULL DEFAULT FALSE,

    explainability_enabled BOOLEAN NOT NULL DEFAULT TRUE,

    max_candidates INTEGER NOT NULL DEFAULT 25,

    --
    -- Blocking configuration
    --

    blocking_rules JSONB NOT NULL DEFAULT '[]'::jsonb,

    --
    -- Execution status
    --

    status VARCHAR(100) NOT NULL DEFAULT 'Pending',

    execution_started_at TIMESTAMPTZ,

    execution_completed_at TIMESTAMPTZ,

    execution_time_ms BIGINT,

    --
    -- Diagnostics
    --

    candidates_evaluated INTEGER,

    blocking_reduction DOUBLE PRECISION,

    warnings JSONB NOT NULL DEFAULT '[]'::jsonb,

    errors JSONB NOT NULL DEFAULT '[]'::jsonb,

    --
    -- Versioning
    --

    engine_version VARCHAR(255),

    --
    -- Audit + metadata
    --

    created_by UUID,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

--
-- ============================================
-- MATCH CANDIDATES
-- ============================================
--

CREATE TABLE IF NOT EXISTS core_mdm.match_candidates (

    --
    -- Identity
    --

    match_candidate_id UUID PRIMARY KEY,

    tenant_id UUID NOT NULL,

    request_id UUID NOT NULL,

    --
    -- Entity references
    --

    source_entity_id UUID NOT NULL,

    matched_entity_id UUID NOT NULL,

    --
    -- Match results
    --

    match_status VARCHAR(100) NOT NULL,

    match_score DOUBLE PRECISION NOT NULL,

    confidence_score DOUBLE PRECISION,

    vector_similarity DOUBLE PRECISION,

    graph_similarity DOUBLE PRECISION,

    ai_score DOUBLE PRECISION,

    survivorship_compatibility DOUBLE PRECISION,

    --
    -- Decisioning
    --

    recommended_for_merge BOOLEAN NOT NULL DEFAULT FALSE,

    requires_human_review BOOLEAN NOT NULL DEFAULT FALSE,

    auto_approved BOOLEAN NOT NULL DEFAULT FALSE,

    approved_by UUID,

    approved_at TIMESTAMPTZ,

    rejection_reason TEXT,

    --
    -- Explainability
    --

    explanations JSONB NOT NULL DEFAULT '[]'::jsonb,

    policy_decisions JSONB NOT NULL DEFAULT '[]'::jsonb,

    --
    -- Ranking
    --

    candidate_rank INTEGER,

    --
    -- Metadata
    --

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    --
    -- Constraints
    --

    CONSTRAINT fk_match_candidates_request
        FOREIGN KEY (request_id)
        REFERENCES core_mdm.match_requests(request_id)
        ON DELETE CASCADE
);

--
-- ============================================
-- FIELD MATCH RESULTS
-- ============================================
--

CREATE TABLE IF NOT EXISTS core_mdm.field_match_results (

    --
    -- Identity
    --

    field_match_id UUID PRIMARY KEY,

    tenant_id UUID NOT NULL,

    request_id UUID NOT NULL,

    match_candidate_id UUID,

    --
    -- Entity references
    --

    source_entity_id UUID NOT NULL,

    matched_entity_id UUID NOT NULL,

    --
    -- Field comparison
    --

    field_name VARCHAR(255) NOT NULL,

    source_value JSONB,

    candidate_value JSONB,

    normalized_source_value JSONB,

    normalized_candidate_value JSONB,

    --
    -- Matching metrics
    --

    score DOUBLE PRECISION NOT NULL,

    confidence_score DOUBLE PRECISION,

    semantic_similarity DOUBLE PRECISION,

    vector_similarity DOUBLE PRECISION,

    --
    -- Matching strategy
    --

    strategy VARCHAR(255) NOT NULL,

    algorithm VARCHAR(255),

    --
    -- Explainability
    --

    explanation JSONB NOT NULL DEFAULT '[]'::jsonb,

    reasoning TEXT,

    --
    -- Metadata
    --

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    --
    -- Constraints
    --

    CONSTRAINT fk_field_match_request
        FOREIGN KEY (request_id)
        REFERENCES core_mdm.match_requests(request_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_field_match_candidate
        FOREIGN KEY (match_candidate_id)
        REFERENCES core_mdm.match_candidates(match_candidate_id)
        ON DELETE CASCADE
);

--
-- ============================================
-- MATCH CLUSTERS
-- ============================================
--

CREATE TABLE IF NOT EXISTS core_mdm.match_clusters (

    --
    -- Identity
    --

    cluster_id UUID PRIMARY KEY,

    tenant_id UUID NOT NULL,

    request_id UUID,

    --
    -- Cluster details
    --

    entity_ids JSONB NOT NULL DEFAULT '[]'::jsonb,

    confidence DOUBLE PRECISION NOT NULL,

    suggested_master UUID,

    auto_merge_recommended BOOLEAN NOT NULL DEFAULT FALSE,

    requires_review BOOLEAN NOT NULL DEFAULT FALSE,

    --
    -- Explainability
    --

    explanations JSONB NOT NULL DEFAULT '[]'::jsonb,

    --
    -- Metadata
    --

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

--
-- ============================================
-- MATCH REVIEW QUEUE
-- ============================================
--

CREATE TABLE IF NOT EXISTS core_mdm.match_review_queue (

    review_id UUID PRIMARY KEY,

    tenant_id UUID NOT NULL,

    request_id UUID NOT NULL,

    match_candidate_id UUID NOT NULL,

    assigned_to UUID,

    review_status VARCHAR(100) NOT NULL DEFAULT 'Pending',

    review_notes TEXT,

    reviewed_by UUID,

    reviewed_at TIMESTAMPTZ,

    priority INTEGER NOT NULL DEFAULT 5,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_review_request
        FOREIGN KEY (request_id)
        REFERENCES core_mdm.match_requests(request_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_review_candidate
        FOREIGN KEY (match_candidate_id)
        REFERENCES core_mdm.match_candidates(match_candidate_id)
        ON DELETE CASCADE
);

--
-- ============================================
-- INDEXES : MATCH REQUESTS
-- ============================================
--

CREATE INDEX IF NOT EXISTS idx_match_requests_tenant
ON core_mdm.match_requests(tenant_id);

CREATE INDEX IF NOT EXISTS idx_match_requests_entity_type
ON core_mdm.match_requests(entity_type);

CREATE INDEX IF NOT EXISTS idx_match_requests_status
ON core_mdm.match_requests(status);

CREATE INDEX IF NOT EXISTS idx_match_requests_strategy
ON core_mdm.match_requests(strategy);

CREATE INDEX IF NOT EXISTS idx_match_requests_created
ON core_mdm.match_requests(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_match_requests_correlation
ON core_mdm.match_requests(correlation_id);

CREATE INDEX IF NOT EXISTS idx_match_requests_metadata
ON core_mdm.match_requests
USING GIN(metadata);

CREATE INDEX IF NOT EXISTS idx_match_requests_blocking_rules
ON core_mdm.match_requests
USING GIN(blocking_rules);

--
-- ============================================
-- INDEXES : MATCH CANDIDATES
-- ============================================
--

CREATE INDEX IF NOT EXISTS idx_match_candidates_tenant
ON core_mdm.match_candidates(tenant_id);

CREATE INDEX IF NOT EXISTS idx_match_candidates_request
ON core_mdm.match_candidates(request_id);

CREATE INDEX IF NOT EXISTS idx_match_candidates_source
ON core_mdm.match_candidates(source_entity_id);

CREATE INDEX IF NOT EXISTS idx_match_candidates_matched
ON core_mdm.match_candidates(matched_entity_id);

CREATE INDEX IF NOT EXISTS idx_match_candidates_status
ON core_mdm.match_candidates(match_status);

CREATE INDEX IF NOT EXISTS idx_match_candidates_score
ON core_mdm.match_candidates(match_score DESC);

CREATE INDEX IF NOT EXISTS idx_match_candidates_review
ON core_mdm.match_candidates(requires_human_review);

CREATE INDEX IF NOT EXISTS idx_match_candidates_merge
ON core_mdm.match_candidates(recommended_for_merge);

CREATE INDEX IF NOT EXISTS idx_match_candidates_created
ON core_mdm.match_candidates(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_match_candidates_explanations
ON core_mdm.match_candidates
USING GIN(explanations);

CREATE INDEX IF NOT EXISTS idx_match_candidates_policy
ON core_mdm.match_candidates
USING GIN(policy_decisions);

CREATE INDEX IF NOT EXISTS idx_match_candidates_metadata
ON core_mdm.match_candidates
USING GIN(metadata);

--
-- ============================================
-- INDEXES : FIELD MATCH RESULTS
-- ============================================
--

CREATE INDEX IF NOT EXISTS idx_field_match_tenant
ON core_mdm.field_match_results(tenant_id);

CREATE INDEX IF NOT EXISTS idx_field_match_request
ON core_mdm.field_match_results(request_id);

CREATE INDEX IF NOT EXISTS idx_field_match_candidate
ON core_mdm.field_match_results(match_candidate_id);

CREATE INDEX IF NOT EXISTS idx_field_match_field
ON core_mdm.field_match_results(field_name);

CREATE INDEX IF NOT EXISTS idx_field_match_strategy
ON core_mdm.field_match_results(strategy);

CREATE INDEX IF NOT EXISTS idx_field_match_score
ON core_mdm.field_match_results(score DESC);

CREATE INDEX IF NOT EXISTS idx_field_match_metadata
ON core_mdm.field_match_results
USING GIN(metadata);

CREATE INDEX IF NOT EXISTS idx_field_match_explanation
ON core_mdm.field_match_results
USING GIN(explanation);

CREATE INDEX IF NOT EXISTS idx_field_match_source_value
ON core_mdm.field_match_results
USING GIN(source_value);

CREATE INDEX IF NOT EXISTS idx_field_match_candidate_value
ON core_mdm.field_match_results
USING GIN(candidate_value);

--
-- ============================================
-- INDEXES : MATCH CLUSTERS
-- ============================================
--

CREATE INDEX IF NOT EXISTS idx_match_clusters_tenant
ON core_mdm.match_clusters(tenant_id);

CREATE INDEX IF NOT EXISTS idx_match_clusters_request
ON core_mdm.match_clusters(request_id);

CREATE INDEX IF NOT EXISTS idx_match_clusters_confidence
ON core_mdm.match_clusters(confidence DESC);

CREATE INDEX IF NOT EXISTS idx_match_clusters_entities
ON core_mdm.match_clusters
USING GIN(entity_ids);

CREATE INDEX IF NOT EXISTS idx_match_clusters_metadata
ON core_mdm.match_clusters
USING GIN(metadata);

--
-- ============================================
-- INDEXES : REVIEW QUEUE
-- ============================================
--

CREATE INDEX IF NOT EXISTS idx_match_review_tenant
ON core_mdm.match_review_queue(tenant_id);

CREATE INDEX IF NOT EXISTS idx_match_review_request
ON core_mdm.match_review_queue(request_id);

CREATE INDEX IF NOT EXISTS idx_match_review_candidate
ON core_mdm.match_review_queue(match_candidate_id);

CREATE INDEX IF NOT EXISTS idx_match_review_status
ON core_mdm.match_review_queue(review_status);

CREATE INDEX IF NOT EXISTS idx_match_review_priority
ON core_mdm.match_review_queue(priority DESC);

CREATE INDEX IF NOT EXISTS idx_match_review_assigned
ON core_mdm.match_review_queue(assigned_to);

--
-- ============================================
-- UPDATED_AT TRIGGERS
-- ============================================
--

CREATE OR REPLACE FUNCTION core_mdm.update_matching_updated_at()
RETURNS TRIGGER
AS $$
BEGIN

    NEW.updated_at = NOW();

    RETURN NEW;
END;

$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_match_requests_updated
ON core_mdm.match_requests;

CREATE TRIGGER trg_match_requests_updated
BEFORE UPDATE
ON core_mdm.match_requests
FOR EACH ROW
EXECUTE FUNCTION core_mdm.update_matching_updated_at();

DROP TRIGGER IF EXISTS trg_match_candidates_updated
ON core_mdm.match_candidates;

CREATE TRIGGER trg_match_candidates_updated
BEFORE UPDATE
ON core_mdm.match_candidates
FOR EACH ROW
EXECUTE FUNCTION core_mdm.update_matching_updated_at();

DROP TRIGGER IF EXISTS trg_match_review_updated
ON core_mdm.match_review_queue;

CREATE TRIGGER trg_match_review_updated
BEFORE UPDATE
ON core_mdm.match_review_queue
FOR EACH ROW
EXECUTE FUNCTION core_mdm.update_matching_updated_at();

--
-- ============================================
-- COMMENTS
-- ============================================
--

COMMENT ON TABLE core_mdm.match_requests
IS 'Stores match execution requests and runtime diagnostics';

COMMENT ON TABLE core_mdm.match_candidates
IS 'Stores ranked entity match candidates';

COMMENT ON TABLE core_mdm.field_match_results
IS 'Stores field-level comparison and scoring results';

COMMENT ON TABLE core_mdm.match_clusters
IS 'Stores suggested entity clusters for merge/grouping';

COMMENT ON TABLE core_mdm.match_review_queue
IS 'Human review workflow queue for ambiguous matches';