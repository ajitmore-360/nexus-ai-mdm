CREATE TABLE lineage.entity_lineage (

    lineage_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    tenant_id UUID NOT NULL,

    source_entity_id UUID NOT NULL,

    target_entity_id UUID NOT NULL,

    lineage_type VARCHAR(100) NOT NULL,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_lineage_source
ON lineage.entity_lineage(source_entity_id);

CREATE INDEX idx_lineage_target
ON lineage.entity_lineage(target_entity_id);