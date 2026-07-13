-- Migration 0019: Hierarchy Management (closure table pattern)
-- Supports org charts, product trees, account hierarchies, geographic rollups.
-- Closure table gives O(1) "get all descendants" and "get all ancestors" queries.
-- parent_entity_id = direct parent link (for UI and quick parent lookups).
-- entity_hierarchies = ALL ancestor-descendant pairs (for traversal at any depth).

ALTER TABLE core_mdm.entities
    ADD COLUMN IF NOT EXISTS parent_entity_id UUID REFERENCES core_mdm.entities(entity_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_entities_parent
    ON core_mdm.entities (parent_entity_id)
    WHERE parent_entity_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS core_mdm.entity_hierarchies (
    ancestor_id   UUID    NOT NULL REFERENCES core_mdm.entities(entity_id) ON DELETE CASCADE,
    descendant_id UUID    NOT NULL REFERENCES core_mdm.entities(entity_id) ON DELETE CASCADE,
    depth         INTEGER NOT NULL DEFAULT 0 CHECK (depth >= 0),
    tenant_id     UUID    NOT NULL,
    PRIMARY KEY (ancestor_id, descendant_id)
);

CREATE INDEX IF NOT EXISTS idx_hierarchy_descendant ON core_mdm.entity_hierarchies (descendant_id, tenant_id);
CREATE INDEX IF NOT EXISTS idx_hierarchy_ancestor   ON core_mdm.entity_hierarchies (ancestor_id, tenant_id);
CREATE INDEX IF NOT EXISTS idx_hierarchy_depth      ON core_mdm.entity_hierarchies (tenant_id, depth);

ALTER TABLE core_mdm.entity_hierarchies ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON core_mdm.entity_hierarchies
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- Stored function: atomically set a new parent for an entity.
-- Deletes the entity's existing closure rows, re-inserts self-reference,
-- then inserts one row per ancestor of the new parent.
-- Call this instead of directly updating parent_entity_id.
CREATE OR REPLACE FUNCTION core_mdm.set_entity_parent(
    p_entity_id UUID,
    p_parent_id UUID,
    p_tenant_id UUID
) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    -- Remove all existing hierarchy entries where this entity is a descendant
    DELETE FROM core_mdm.entity_hierarchies WHERE descendant_id = p_entity_id;

    -- Always insert self-reference (depth=0)
    INSERT INTO core_mdm.entity_hierarchies (ancestor_id, descendant_id, depth, tenant_id)
    VALUES (p_entity_id, p_entity_id, 0, p_tenant_id)
    ON CONFLICT (ancestor_id, descendant_id) DO NOTHING;

    IF p_parent_id IS NOT NULL THEN
        -- For each ancestor of the new parent (including the parent itself), add a row
        INSERT INTO core_mdm.entity_hierarchies (ancestor_id, descendant_id, depth, tenant_id)
        SELECT h.ancestor_id, p_entity_id, h.depth + 1, p_tenant_id
        FROM   core_mdm.entity_hierarchies h
        WHERE  h.descendant_id = p_parent_id;
    END IF;

    -- Update the direct parent pointer on the entity row
    UPDATE core_mdm.entities
    SET    parent_entity_id = p_parent_id,
           updated_at       = NOW()
    WHERE  id = p_entity_id
      AND  tenant_id = p_tenant_id;
END;
$$;
