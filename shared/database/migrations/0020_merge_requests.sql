-- ─────────────────────────────────────────────────────────────────────────────
-- 0020: Merge Requests table + Unmerge support
-- Tracks full merge lifecycle so unmerge can restore pre-merge entity state.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.merge_requests (
    id                         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                  UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    merge_request_id           UUID        NOT NULL,            -- from the contracts MergeRequest
    golden_record_id           UUID,                            -- set after merge completes
    primary_entity_id          UUID        NOT NULL,
    candidate_entity_ids       UUID[]      NOT NULL DEFAULT '{}',
    status                     TEXT        NOT NULL DEFAULT 'Pending'
                                           CHECK (status IN ('Pending','Processing','Completed','Failed','Unmerged')),
    initiated_by               UUID,
    reason                     TEXT,
    -- JSONB snapshot of each entity's attributes before merge (for unmerge restore)
    pre_merge_entity_snapshots JSONB       NOT NULL DEFAULT '[]',
    error_message              TEXT,
    started_at                 TIMESTAMPTZ,
    completed_at               TIMESTAMPTZ,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_merge_requests_merge_id
    ON core_mdm.merge_requests (tenant_id, merge_request_id);

CREATE INDEX IF NOT EXISTS idx_merge_requests_golden
    ON core_mdm.merge_requests (tenant_id, golden_record_id)
    WHERE golden_record_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_merge_requests_status
    ON core_mdm.merge_requests (tenant_id, status);

ALTER TABLE core_mdm.merge_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON core_mdm.merge_requests
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);
