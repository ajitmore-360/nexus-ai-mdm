CREATE INDEX idx_entity_embeddings_vector
ON core_mdm.entity_embeddings
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);