CREATE TABLE core_mdm.attribute_definitions (

    attribute_definition_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    tenant_id UUID NOT NULL
        REFERENCES core_mdm.tenants(tenant_id),

    entity_type_id UUID NOT NULL
        REFERENCES core_mdm.entity_types(entity_type_id),

    attribute_name VARCHAR(255) NOT NULL,

    data_type VARCHAR(100) NOT NULL,

    required BOOLEAN NOT NULL DEFAULT FALSE,

    searchable BOOLEAN NOT NULL DEFAULT TRUE,

    vectorizable BOOLEAN NOT NULL DEFAULT TRUE,

    pii BOOLEAN NOT NULL DEFAULT FALSE,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_attribute_defs_entity
ON core_mdm.attribute_definitions(entity_type_id);