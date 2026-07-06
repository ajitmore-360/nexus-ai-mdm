-- ============================================================
-- 002012 — GDPR hard-delete stored procedure
--
-- core_mdm.gdpr_erase_entity(p_tenant_id, p_entity_id)
--   Permanently removes an entity and every record that points
--   to it, in FK-safe order.  Returns the number of rows erased
--   from core_mdm.entities (1 = found and deleted, 0 = not found).
--
-- Callers are responsible for:
--   • Verifying the requester has admin/SuperAdmin role
--   • Writing a GDPR-erasure audit event after this function returns
-- ============================================================

CREATE OR REPLACE FUNCTION core_mdm.gdpr_erase_entity(
    p_tenant_id UUID,
    p_entity_id UUID
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_deleted INTEGER := 0;
BEGIN
    -- ── 1. Relationships ────────────────────────────────────────────────────
    DELETE FROM core_mdm.entity_relationships
    WHERE tenant_id = p_tenant_id
      AND (from_entity_id = p_entity_id OR to_entity_id = p_entity_id);

    -- ── 2. Match requests — candidates + scores cascade via FK ──────────────
    DELETE FROM core_mdm.match_requests
    WHERE tenant_id = p_tenant_id
      AND (source_entity_id = p_entity_id OR canonical_entity_id = p_entity_id);

    -- ── 3. Match review queue items that reference this entity ───────────────
    DELETE FROM core_mdm.match_review_queue
    WHERE tenant_id = p_tenant_id
      AND entity_ids @> to_jsonb(p_entity_id);

    -- ── 4. Lineage (source or target) ────────────────────────────────────────
    DELETE FROM lineage.entity_lineage
    WHERE tenant_id = p_tenant_id
      AND (source_entity_id = p_entity_id OR target_entity_id = p_entity_id);

    -- ── 5. Vector embeddings ─────────────────────────────────────────────────
    DELETE FROM core_mdm.entity_vectors
    WHERE tenant_id = p_tenant_id
      AND entity_id = p_entity_id;

    -- ── 6. Attributes (PII is here) ──────────────────────────────────────────
    DELETE FROM core_mdm.entity_attributes
    WHERE tenant_id = p_tenant_id
      AND entity_id = p_entity_id;

    -- ── 7. Golden attributes that originated from this entity ────────────────
    DELETE FROM core_mdm.golden_attributes
    WHERE tenant_id = p_tenant_id
      AND source_entity_id = p_entity_id;

    -- ── 8. Consent records ───────────────────────────────────────────────────
    DELETE FROM core_mdm.consent_records
    WHERE tenant_id = p_tenant_id
      AND entity_id = p_entity_id;

    -- ── 9. Entity itself ─────────────────────────────────────────────────────
    DELETE FROM core_mdm.entities
    WHERE tenant_id = p_tenant_id
      AND entity_id = p_entity_id;

    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION core_mdm.gdpr_erase_entity(UUID, UUID) IS
    'Permanently erases all PII for a given entity (GDPR Art. 17). '
    'Caller must log an audit event and verify admin role before invoking.';
