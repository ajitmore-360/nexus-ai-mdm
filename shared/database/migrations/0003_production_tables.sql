-- =============================================================================
-- Migration: 0003_production_tables
-- Creates all tables required for production operation across every service.
-- This migration is idempotent (IF NOT EXISTS / DO NOTHING guards everywhere).
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- TENANTS  (core_mdm.tenants)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.tenants (
    tenant_id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_code      CITEXT      NOT NULL UNIQUE,
    display_name     TEXT        NOT NULL,
    plan             TEXT        NOT NULL DEFAULT 'enterprise',
    status           TEXT        NOT NULL DEFAULT 'active',
    -- Quotas
    max_entities     BIGINT      DEFAULT 10000000,
    max_users        INT         DEFAULT 100,
    max_source_sys   INT         DEFAULT 50,
    -- AI config (per-tenant model overrides)
    llm_model        TEXT        DEFAULT 'llama3.2:8b',
    embedding_model  TEXT        DEFAULT 'nomic-embed-text',
    -- Feature flags
    features         JSONB       NOT NULL DEFAULT '{"ai_matching":true,"rag_copilot":true,"vector_blocking":true}',
    settings         JSONB       NOT NULL DEFAULT '{}',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tenants_code ON core_mdm.tenants (tenant_code);

-- Seed a default tenant so local dev works without extra setup
INSERT INTO core_mdm.tenants (tenant_id, tenant_code, display_name)
VALUES ('00000000-0000-0000-0000-000000000001', 'default', 'Default Organisation')
ON CONFLICT (tenant_code) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- USERS  (core_mdm.users)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.users (
    user_id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id      UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    email          CITEXT      NOT NULL,
    display_name   TEXT        NOT NULL,
    role           TEXT        NOT NULL DEFAULT 'steward',
    status         TEXT        NOT NULL DEFAULT 'active',
    avatar_url     TEXT,
    preferences    JSONB       NOT NULL DEFAULT '{}',
    last_login_at  TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(tenant_id, email)
);

CREATE INDEX IF NOT EXISTS idx_users_tenant ON core_mdm.users (tenant_id, role);

-- ─────────────────────────────────────────────────────────────────────────────
-- SOURCE SYSTEMS  (core_mdm.source_systems)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.source_systems (
    source_id      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id      UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    name           TEXT        NOT NULL,
    system_type    TEXT        NOT NULL DEFAULT 'crm',
    base_url       TEXT,
    trust_score    FLOAT4      NOT NULL DEFAULT 0.80,
    status         TEXT        NOT NULL DEFAULT 'active',
    config         JSONB       NOT NULL DEFAULT '{}',
    last_sync_at   TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(tenant_id, name)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- ENTITIES  (core_mdm.entities)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.entities (
    entity_id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id          UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    entity_type        TEXT        NOT NULL,
    status             TEXT        NOT NULL DEFAULT 'Active',
    external_ids       JSONB       NOT NULL DEFAULT '{}',
    tags               TEXT[]      NOT NULL DEFAULT '{}',
    metadata           JSONB       NOT NULL DEFAULT '{}',
    trust_score        FLOAT4      DEFAULT 0.0,
    source_system      TEXT,
    golden_record_id   UUID,
    semantic_identity  TEXT,
    vector_namespace   TEXT,
    -- Bitemporal
    valid_from         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    valid_to           TIMESTAMPTZ NOT NULL DEFAULT 'infinity',
    recorded_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Audit
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by         UUID,
    correlation_id     UUID
);

CREATE INDEX IF NOT EXISTS idx_entities_tenant_type
    ON core_mdm.entities (tenant_id, entity_type)
    WHERE valid_to = 'infinity';

CREATE INDEX IF NOT EXISTS idx_entities_golden
    ON core_mdm.entities (tenant_id, golden_record_id)
    WHERE golden_record_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_entities_fts
    ON core_mdm.entities
    USING gin(to_tsvector('english', metadata::text))
    WHERE valid_to = 'infinity';

-- ─────────────────────────────────────────────────────────────────────────────
-- ENTITY ATTRIBUTES  (core_mdm.entity_attributes)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.entity_attributes (
    attribute_id    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL,
    entity_id       UUID        NOT NULL REFERENCES core_mdm.entities(entity_id) ON DELETE CASCADE,
    attribute_key   TEXT        NOT NULL,
    attribute_value JSONB       NOT NULL,
    data_type       TEXT        NOT NULL DEFAULT 'string',
    confidence      FLOAT4,
    source_system   TEXT,
    is_masked       BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_entity_attrs_lookup
    ON core_mdm.entity_attributes (tenant_id, attribute_key, entity_id);

CREATE INDEX IF NOT EXISTS idx_entity_attrs_value
    ON core_mdm.entity_attributes
    USING gin(attribute_value jsonb_path_ops);

-- ─────────────────────────────────────────────────────────────────────────────
-- GOLDEN RECORDS  (core_mdm.golden_records)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.golden_records (
    golden_record_id UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    entity_type      TEXT        NOT NULL,
    status           TEXT        NOT NULL DEFAULT 'Active',
    lifecycle_stage  TEXT        NOT NULL DEFAULT 'Created',
    trust_score      FLOAT4      DEFAULT 0.0,
    quality_score    FLOAT4      DEFAULT 0.0,
    completeness     FLOAT4      DEFAULT 0.0,
    source_entities  UUID[]      NOT NULL DEFAULT '{}',
    semantic_identity TEXT,
    vector_namespace  TEXT,
    metadata         JSONB       NOT NULL DEFAULT '{}',
    valid_from        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    valid_to          TIMESTAMPTZ NOT NULL DEFAULT 'infinity',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_golden_records_tenant
    ON core_mdm.golden_records (tenant_id, entity_type)
    WHERE valid_to = 'infinity';

-- ─────────────────────────────────────────────────────────────────────────────
-- GOLDEN ATTRIBUTES  (core_mdm.golden_attributes)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.golden_attributes (
    golden_attribute_id UUID       PRIMARY KEY DEFAULT gen_random_uuid(),
    golden_record_id    UUID       NOT NULL REFERENCES core_mdm.golden_records(golden_record_id) ON DELETE CASCADE,
    tenant_id           UUID       NOT NULL,
    attribute_key       TEXT       NOT NULL,
    attribute_value     JSONB      NOT NULL,
    source_system       TEXT,
    survivorship_rule   TEXT,
    confidence          FLOAT4,
    human_override      BOOLEAN    NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_golden_attrs_record
    ON core_mdm.golden_attributes (golden_record_id, attribute_key);

-- ─────────────────────────────────────────────────────────────────────────────
-- MATCH CANDIDATES  (core_mdm.match_candidates)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.match_candidates (
    match_candidate_id    UUID     PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id             UUID     NOT NULL,
    request_id            UUID     NOT NULL,
    source_entity_id      UUID     NOT NULL,
    matched_entity_id     UUID     NOT NULL,
    match_status          TEXT     NOT NULL DEFAULT 'Pending',
    match_score           FLOAT4   NOT NULL DEFAULT 0.0,
    confidence_score      FLOAT4,
    vector_similarity     FLOAT4,
    graph_similarity      FLOAT4,
    ai_score              FLOAT4,
    survivorship_compatibility FLOAT4,
    recommended_for_merge BOOLEAN  NOT NULL DEFAULT FALSE,
    requires_human_review BOOLEAN  NOT NULL DEFAULT FALSE,
    explanations          JSONB    NOT NULL DEFAULT '[]',
    policy_decisions      JSONB    NOT NULL DEFAULT '[]',
    metadata              JSONB    NOT NULL DEFAULT '{}',
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_match_candidates_tenant_req
    ON core_mdm.match_candidates (tenant_id, request_id);

CREATE INDEX IF NOT EXISTS idx_match_candidates_review
    ON core_mdm.match_candidates (tenant_id, requires_human_review)
    WHERE requires_human_review = TRUE;

-- ─────────────────────────────────────────────────────────────────────────────
-- FIELD MATCH RESULTS  (core_mdm.field_match_results)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.field_match_results (
    field_match_id      UUID     PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID     NOT NULL,
    request_id          UUID     NOT NULL,
    source_entity_id    UUID     NOT NULL,
    matched_entity_id   UUID     NOT NULL,
    field_name          TEXT     NOT NULL,
    source_value        JSONB,
    candidate_value     JSONB,
    score               FLOAT4   NOT NULL DEFAULT 0.0,
    confidence_score    FLOAT4,
    strategy            TEXT     NOT NULL DEFAULT 'Hybrid',
    semantic_similarity FLOAT4,
    explanation         JSONB    NOT NULL DEFAULT '[]',
    metadata            JSONB    NOT NULL DEFAULT '{}',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_field_match_results_lookup
    ON core_mdm.field_match_results (tenant_id, request_id, matched_entity_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- SURVIVORSHIP RULES  (core_mdm.survivorship_rules)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.survivorship_rules (
    rule_id              UUID     PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id            UUID     NOT NULL,
    rule_name            TEXT     NOT NULL,
    description          TEXT,
    entity_type          TEXT     NOT NULL,
    attribute_key        TEXT     NOT NULL,
    strategy             TEXT     NOT NULL DEFAULT 'TrustedSource',
    source_priority      JSONB    NOT NULL DEFAULT '[]',
    min_confidence       FLOAT4   DEFAULT 0.0,
    ai_assisted          BOOLEAN  NOT NULL DEFAULT FALSE,
    allow_manual_override BOOLEAN NOT NULL DEFAULT TRUE,
    status               TEXT     NOT NULL DEFAULT 'Active',
    priority             INT      NOT NULL DEFAULT 100,
    effective_from       TIMESTAMPTZ,
    effective_to         TIMESTAMPTZ,
    metadata             JSONB    NOT NULL DEFAULT '{}',
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(tenant_id, entity_type, attribute_key, rule_name)
);

CREATE INDEX IF NOT EXISTS idx_survivorship_rules_tenant_type
    ON core_mdm.survivorship_rules (tenant_id, entity_type, status);

-- ─────────────────────────────────────────────────────────────────────────────
-- SURVIVORSHIP EXECUTIONS  (core_mdm.survivorship_executions)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.survivorship_executions (
    execution_id     UUID     PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID     NOT NULL,
    golden_record_id UUID     NOT NULL,
    entity_ids       UUID[]   NOT NULL DEFAULT '{}',
    rules_applied    INT      NOT NULL DEFAULT 0,
    overall_confidence FLOAT4,
    started_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at     TIMESTAMPTZ,
    metadata         JSONB    NOT NULL DEFAULT '{}'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- OUTBOX EVENTS  (event_store.outbox_events)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS event_store.outbox_events (
    event_id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL,
    aggregate_type   TEXT        NOT NULL,
    aggregate_id     UUID        NOT NULL,
    event_type       TEXT        NOT NULL,
    event_payload    JSONB       NOT NULL,
    event_metadata   JSONB       NOT NULL DEFAULT '{}',
    topic_name       TEXT        NOT NULL,
    status           TEXT        NOT NULL DEFAULT 'pending',
    attempts         INT         NOT NULL DEFAULT 0,
    last_error       TEXT,
    partition_key    TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_outbox_pending
    ON event_store.outbox_events (tenant_id, status, created_at)
    WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_outbox_aggregate
    ON event_store.outbox_events (tenant_id, aggregate_type, aggregate_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- GOVERNANCE: POLICY RULES  (governance.policy_rules)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS governance.policy_rules (
    rule_id      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id    UUID        NOT NULL,
    name         TEXT        NOT NULL,
    description  TEXT,
    rule_type    TEXT        NOT NULL,
    entity_type  TEXT,
    field_name   TEXT,
    rego_policy  TEXT        NOT NULL DEFAULT 'package mdm.policy\ndefault allow = true',
    priority     INT         NOT NULL DEFAULT 100,
    status       TEXT        NOT NULL DEFAULT 'active',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(tenant_id, name)
);

CREATE INDEX IF NOT EXISTS idx_policy_rules_tenant_type
    ON governance.policy_rules (tenant_id, entity_type, status)
    WHERE status = 'active';

-- ─────────────────────────────────────────────────────────────────────────────
-- AUDIT: GDPR REQUESTS  (audit.gdpr_requests)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS audit.gdpr_requests (
    audit_id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL,
    subject_id       UUID        NOT NULL,
    request_type     TEXT        NOT NULL,
    records_affected BIGINT      NOT NULL DEFAULT 0,
    fields_erased    TEXT[]      NOT NULL DEFAULT '{}',
    requested_by     TEXT,
    completed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gdpr_requests_tenant
    ON audit.gdpr_requests (tenant_id, subject_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- NOTIFICATIONS  (platform.notifications)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS platform.notifications (
    notification_id UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL,
    user_id         UUID,
    notification_type TEXT      NOT NULL,
    title           TEXT        NOT NULL,
    body            TEXT        NOT NULL,
    severity        TEXT        NOT NULL DEFAULT 'info',
    entity_id       UUID,
    entity_type     TEXT,
    action_url      TEXT,
    read            BOOLEAN     NOT NULL DEFAULT FALSE,
    read_at         TIMESTAMPTZ,
    metadata        JSONB       NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_tenant_user
    ON platform.notifications (tenant_id, user_id, read, created_at DESC)
    WHERE read = FALSE;

-- ─────────────────────────────────────────────────────────────────────────────
-- DISTRIBUTION CONNECTORS  (platform.distribution_connectors)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS platform.distribution_connectors (
    connector_id    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL,
    name            TEXT        NOT NULL,
    connector_type  TEXT        NOT NULL,
    target_system   TEXT        NOT NULL,
    endpoint_url    TEXT,
    auth_config     JSONB       NOT NULL DEFAULT '{}',
    entity_types    TEXT[]      NOT NULL DEFAULT '{}',
    status          TEXT        NOT NULL DEFAULT 'active',
    last_run_at     TIMESTAMPTZ,
    config          JSONB       NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(tenant_id, name)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- DISTRIBUTION JOBS  (platform.distribution_jobs)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS platform.distribution_jobs (
    job_id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL,
    connector_id    UUID        NOT NULL REFERENCES platform.distribution_connectors(connector_id),
    entity_id       UUID        NOT NULL,
    entity_type     TEXT        NOT NULL,
    status          TEXT        NOT NULL DEFAULT 'pending',
    attempts        INT         NOT NULL DEFAULT 0,
    max_attempts    INT         NOT NULL DEFAULT 3,
    last_error      TEXT,
    payload         JSONB       NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_distribution_jobs_pending
    ON platform.distribution_jobs (tenant_id, status, created_at)
    WHERE status IN ('pending', 'failed');

COMMENT ON TABLE core_mdm.tenants               IS 'Multi-tenant organisation registry';
COMMENT ON TABLE core_mdm.entities              IS 'Canonical entity records with bitemporal validity';
COMMENT ON TABLE event_store.outbox_events      IS 'Transactional outbox for reliable Kafka publishing';
COMMENT ON TABLE governance.policy_rules        IS 'OPA-evaluated policy rules per tenant';
COMMENT ON TABLE platform.notifications         IS 'Real-time in-app notifications for stewards';
COMMENT ON TABLE platform.distribution_connectors IS 'Downstream distribution connector registry';
