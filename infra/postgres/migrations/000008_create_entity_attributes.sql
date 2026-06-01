CREATE TABLE core_mdm.entity_attributes (

    attribute_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    tenant_id UUID NOT NULL
        REFERENCES core_mdm.tenants(tenant_id),

    entity_id UUID NOT NULL
        REFERENCES core_mdm.entities(entity_id)
        ON DELETE CASCADE,

    attribute_name VARCHAR(255) NOT NULL,

    attribute_value JSONB NOT NULL,

    confidence_score NUMERIC(5,4),

    source_system VARCHAR(255),

    vector_embedding vector(1536),

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_entity_attributes_entity
ON core_mdm.entity_attributes(entity_id);

CREATE INDEX idx_entity_attributes_name
ON core_mdm.entity_attributes(attribute_name);

CREATE INDEX idx_entity_attributes_json
ON core_mdm.entity_attributes
USING GIN(attribute_value);

CREATE INDEX idx_entity_attributes_vector
ON core_mdm.entity_attributes
USING ivfflat (vector_embedding vector_cosine_ops);