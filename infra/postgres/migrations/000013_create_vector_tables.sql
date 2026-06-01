CREATE TABLE ai.rag_chunks (

    chunk_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    tenant_id UUID NOT NULL,

    entity_id UUID,

    chunk_text TEXT NOT NULL,

    embedding vector(1536),

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rag_chunks_embedding
ON ai.rag_chunks
USING ivfflat (embedding vector_cosine_ops);