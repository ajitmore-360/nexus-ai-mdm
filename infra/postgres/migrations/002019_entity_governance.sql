-- Migration 002019: Entity governance — data ownership & approval workflow
-- Adds:
--   core_mdm.entity_type_assignments  — who owns / stewards each entity type
--   core_mdm.entity_approval_requests — Steward→DataOwner approval queue

-- ── 1. Entity-type assignments ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS core_mdm.entity_type_assignments (
    assignment_id    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        uuid        NOT NULL,
    identity_id      uuid        NOT NULL REFERENCES core_mdm.identities(identity_id) ON DELETE CASCADE,
    entity_type_code text        NOT NULL,
    assignment_type  text        NOT NULL CHECK (assignment_type IN ('owner', 'steward')),
    assigned_by      uuid        REFERENCES core_mdm.identities(identity_id),
    assigned_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, identity_id, entity_type_code)
);

-- Exactly ONE owner per entity type per tenant
CREATE UNIQUE INDEX IF NOT EXISTS entity_type_assignments_one_owner_idx
    ON core_mdm.entity_type_assignments (tenant_id, entity_type_code)
    WHERE assignment_type = 'owner';

CREATE INDEX IF NOT EXISTS idx_eta_tenant_type
    ON core_mdm.entity_type_assignments (tenant_id, entity_type_code);

CREATE INDEX IF NOT EXISTS idx_eta_identity
    ON core_mdm.entity_type_assignments (identity_id);

-- ── 2. Entity approval requests ───────────────────────────────────────────────
-- Tracks steward submissions pending Data Owner review.
-- A partial unique index ensures at most one pending request per entity.
CREATE TABLE IF NOT EXISTS core_mdm.entity_approval_requests (
    request_id       uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        uuid        NOT NULL,
    entity_id        uuid        NOT NULL,
    entity_type_code text        NOT NULL,
    submitted_by     uuid        NOT NULL REFERENCES core_mdm.identities(identity_id),
    submitted_at     timestamptz NOT NULL DEFAULT now(),
    reviewed_by      uuid        REFERENCES core_mdm.identities(identity_id),
    reviewed_at      timestamptz,
    status           text        NOT NULL DEFAULT 'pending'
                                 CHECK (status IN ('pending', 'approved', 'rejected')),
    reviewer_notes   text,
    change_summary   text
);

CREATE UNIQUE INDEX IF NOT EXISTS entity_approval_requests_pending_idx
    ON core_mdm.entity_approval_requests (entity_id)
    WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_ear_tenant_status
    ON core_mdm.entity_approval_requests (tenant_id, status);

CREATE INDEX IF NOT EXISTS idx_ear_submitted_by
    ON core_mdm.entity_approval_requests (submitted_by);
