-- =============================================================================
-- Migration: 0002_ai_schema
-- AI schema tables: steward feedback, RAG knowledge base, entity embeddings
-- =============================================================================

-- Steward feedback for adaptive scoring / reinforcement learning
CREATE TABLE IF NOT EXISTS ai.steward_feedback (
    feedback_id       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID         NOT NULL,
    steward_id        UUID         NOT NULL,
    feedback_type     TEXT         NOT NULL,
    source_entity_id  UUID         NOT NULL,
    candidate_id      UUID,
    feature_vector    JSONB        NOT NULL DEFAULT '{}',
    system_decision   TEXT         NOT NULL,
    human_decision    TEXT         NOT NULL,
    notes             TEXT,
    used_in_training  BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_feedback_tenant_type
    ON ai.steward_feedback (tenant_id, feedback_type);

CREATE INDEX IF NOT EXISTS idx_feedback_training
    ON ai.steward_feedback (tenant_id, used_in_training)
    WHERE used_in_training = FALSE;

-- RAG knowledge base (entities, rules, policies as searchable text + embedding)
CREATE TABLE IF NOT EXISTS ai.rag_documents (
    doc_id      UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID         NOT NULL,
    doc_type    TEXT         NOT NULL,
    title       TEXT         NOT NULL,
    content     TEXT         NOT NULL,
    embedding   VECTOR(768),              -- nomic-embed-text produces 768-dim vectors
    metadata    JSONB        NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rag_embedding
    ON ai.rag_documents USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 50);

CREATE INDEX IF NOT EXISTS idx_rag_tenant_type
    ON ai.rag_documents (tenant_id, doc_type);

-- Entity embeddings cache (populated by ai-service embed pipeline)
CREATE TABLE IF NOT EXISTS ai.entity_embeddings (
    embedding_id    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL,
    entity_id       UUID         NOT NULL,
    embedding_model TEXT         NOT NULL,
    embedding       VECTOR(768)  NOT NULL,
    generated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, entity_id, embedding_model)
);

CREATE INDEX IF NOT EXISTS idx_entity_embeddings_ann
    ON ai.entity_embeddings USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

CREATE INDEX IF NOT EXISTS idx_entity_embeddings_lookup
    ON ai.entity_embeddings (tenant_id, entity_id);

-- Anomaly detection results (persisted for UI display)
CREATE TABLE IF NOT EXISTS ai.anomalies (
    anomaly_id      UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL,
    severity        TEXT         NOT NULL,
    category        TEXT         NOT NULL,
    field_name      TEXT,
    entity_type     TEXT,
    source_system   TEXT,
    description     TEXT         NOT NULL,
    affected_count  BIGINT       NOT NULL DEFAULT 0,
    resolved        BOOLEAN      NOT NULL DEFAULT FALSE,
    resolved_at     TIMESTAMPTZ,
    detected_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_anomalies_tenant_active
    ON ai.anomalies (tenant_id, detected_at DESC)
    WHERE resolved = FALSE;

COMMENT ON TABLE ai.steward_feedback  IS 'Human steward override events used for adaptive weight tuning';
COMMENT ON TABLE ai.rag_documents     IS 'Knowledge base for RAG copilot (entities, rules, policies)';
COMMENT ON TABLE ai.entity_embeddings IS 'Semantic embeddings for vector-based entity blocking and search';
COMMENT ON TABLE ai.anomalies         IS 'Detected data quality anomalies persisted for UI consumption';
