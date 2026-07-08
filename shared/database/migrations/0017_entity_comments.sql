-- Migration 0017: Entity Comments & Collaboration
-- Discussion threads on MDM records — stewards capture institutional knowledge
-- without leaving the MDM UI ("deduped from 3 SAP records, keep BP100234").

CREATE TABLE IF NOT EXISTS core_mdm.entity_comments (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    entity_id   UUID        NOT NULL REFERENCES core_mdm.entities(id) ON DELETE CASCADE,
    author_id   UUID        NOT NULL,
    author_name VARCHAR(255) NOT NULL DEFAULT '',
    content     TEXT        NOT NULL CHECK (char_length(content) BETWEEN 1 AND 5000),
    is_edited   BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_entity_comments_entity ON core_mdm.entity_comments (tenant_id, entity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_entity_comments_author ON core_mdm.entity_comments (tenant_id, author_id);

ALTER TABLE core_mdm.entity_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON core_mdm.entity_comments
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);
