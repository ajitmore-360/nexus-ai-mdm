CREATE TABLE core_mdm.entities (

    entity_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    tenant_id UUID NOT NULL
        REFERENCES core_mdm.tenants(tenant_id),

    entity_type_id UUID NOT NULL
        REFERENCES core_mdm.entity_types(entity_type_id),

    entity_code VARCHAR(255),

    status VARCHAR(50) NOT NULL DEFAULT 'ACTIVE',

    source_system VARCHAR(255),

    trust_score NUMERIC(5,4),

    semantic_identity TEXT,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_entities_tenant
ON core_mdm.entities(tenant_id);

CREATE INDEX idx_entities_entity_type
ON core_mdm.entities(entity_type_id);

CREATE INDEX idx_entities_metadata
ON core_mdm.entities
USING GIN(metadata);