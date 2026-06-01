--
-- ============================================================
-- GLOBAL INDEXES
-- File: 000017_create_indexes.sql
-- ============================================================
--
-- This migration creates enterprise-grade indexes for:
--
-- 1. Multi-tenant isolation
-- 2. High-performance MDM search
-- 3. Survivorship queries
-- 4. Matching engine acceleration
-- 5. Vector + semantic retrieval
-- 6. Event sourcing workloads
-- 7. Audit & lineage queries
-- 8. Time-series optimization
-- ============================================================
--

--
-- ============================================================
-- ENTITIES
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_entities_tenant_entity_type
ON core_mdm.entities(
    tenant_id,
    entity_type_id
);

CREATE INDEX IF NOT EXISTS idx_entities_status
ON core_mdm.entities(status);

CREATE INDEX IF NOT EXISTS idx_entities_created_at
ON core_mdm.entities(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_entities_updated_at
ON core_mdm.entities(updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_entities_external_ref
ON core_mdm.entities(external_reference);

CREATE INDEX IF NOT EXISTS idx_entities_mastered
ON core_mdm.entities(is_mastered);

CREATE INDEX IF NOT EXISTS idx_entities_search_vector
ON core_mdm.entities
USING GIN(search_vector);

CREATE INDEX IF NOT EXISTS idx_entities_metadata_gin
ON core_mdm.entities
USING GIN(metadata);

--
-- ============================================================
-- ENTITY ATTRIBUTES
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_entity_attributes_entity
ON core_mdm.entity_attributes(entity_id);

CREATE INDEX IF NOT EXISTS idx_entity_attributes_attribute
ON core_mdm.entity_attributes(attribute_id);

CREATE INDEX IF NOT EXISTS idx_entity_attributes_key
ON core_mdm.entity_attributes(attribute_key);

CREATE INDEX IF NOT EXISTS idx_entity_attributes_searchable
ON core_mdm.entity_attributes(searchable_value);

CREATE INDEX IF NOT EXISTS idx_entity_attributes_created
ON core_mdm.entity_attributes(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_entity_attributes_metadata_gin
ON core_mdm.entity_attributes
USING GIN(metadata);

CREATE INDEX IF NOT EXISTS idx_entity_attributes_value_gin
ON core_mdm.entity_attributes
USING GIN(attribute_value);

--
-- ============================================================
-- GOLDEN RECORDS
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_golden_records_tenant
ON core_mdm.golden_records(tenant_id);

CREATE INDEX IF NOT EXISTS idx_golden_records_entity_type
ON core_mdm.golden_records(entity_type_id);

CREATE INDEX IF NOT EXISTS idx_golden_records_status
ON core_mdm.golden_records(status);

CREATE INDEX IF NOT EXISTS idx_golden_records_lifecycle
ON core_mdm.golden_records(lifecycle_stage);

CREATE INDEX IF NOT EXISTS idx_golden_records_semantic_identity
ON core_mdm.golden_records(semantic_identity);

CREATE INDEX IF NOT EXISTS idx_golden_records_created
ON core_mdm.golden_records(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_golden_records_updated
ON core_mdm.golden_records(updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_golden_records_metadata_gin
ON core_mdm.golden_records
USING GIN(metadata);

CREATE INDEX IF NOT EXISTS idx_golden_records_source_entities_gin
ON core_mdm.golden_records
USING GIN(source_entities);

--
-- ============================================================
-- GOLDEN ATTRIBUTES
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_golden_attributes_record_key
ON core_mdm.golden_attributes(
    golden_record_id,
    attribute_key
);

CREATE INDEX IF NOT EXISTS idx_golden_attributes_confidence
ON core_mdm.golden_attributes(confidence_score DESC);

CREATE INDEX IF NOT EXISTS idx_golden_attributes_survivorship
ON core_mdm.golden_attributes(survivorship_strategy);

CREATE INDEX IF NOT EXISTS idx_golden_attributes_vector_enabled
ON core_mdm.golden_attributes(vector_enabled);

CREATE INDEX IF NOT EXISTS idx_golden_attributes_searchable_value
ON core_mdm.golden_attributes(searchable_value);

CREATE INDEX IF NOT EXISTS idx_golden_attributes_metadata_gin_2
ON core_mdm.golden_attributes
USING GIN(metadata);

--
-- ============================================================
-- MATCH REQUESTS
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_match_requests_tenant_status
ON core_mdm.match_requests(
    tenant_id,
    status
);

CREATE INDEX IF NOT EXISTS idx_match_requests_created
ON core_mdm.match_requests(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_match_requests_strategy
ON core_mdm.match_requests(strategy);

CREATE INDEX IF NOT EXISTS idx_match_requests_entity_type
ON core_mdm.match_requests(entity_type);

--
-- ============================================================
-- MATCH CANDIDATES
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_match_candidates_request_score
ON core_mdm.match_candidates(
    request_id,
    match_score DESC
);

CREATE INDEX IF NOT EXISTS idx_match_candidates_review
ON core_mdm.match_candidates(
    requires_human_review,
    created_at DESC
);

CREATE INDEX IF NOT EXISTS idx_match_candidates_merge
ON core_mdm.match_candidates(
    recommended_for_merge,
    match_score DESC
);

CREATE INDEX IF NOT EXISTS idx_match_candidates_metadata_gin
ON core_mdm.match_candidates
USING GIN(metadata);

--
-- ============================================================
-- FIELD MATCH RESULTS
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_field_match_results_request
ON core_mdm.field_match_results(request_id);

CREATE INDEX IF NOT EXISTS idx_field_match_results_field
ON core_mdm.field_match_results(field_name);

CREATE INDEX IF NOT EXISTS idx_field_match_results_strategy
ON core_mdm.field_match_results(strategy);

CREATE INDEX IF NOT EXISTS idx_field_match_results_score
ON core_mdm.field_match_results(score DESC);

--
-- ============================================================
-- SURVIVORSHIP EXECUTIONS
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_survivorship_exec_tenant
ON core_mdm.survivorship_executions(tenant_id);

CREATE INDEX IF NOT EXISTS idx_survivorship_exec_golden_record
ON core_mdm.survivorship_executions(golden_record_id);

CREATE INDEX IF NOT EXISTS idx_survivorship_exec_created
ON core_mdm.survivorship_executions(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_survivorship_exec_success
ON core_mdm.survivorship_executions(success);

CREATE INDEX IF NOT EXISTS idx_survivorship_exec_metadata_gin
ON core_mdm.survivorship_executions
USING GIN(metadata);

--
-- ============================================================
-- SURVIVORSHIP EVALUATIONS
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_survivorship_eval_execution
ON core_mdm.survivorship_evaluations(execution_id);

CREATE INDEX IF NOT EXISTS idx_survivorship_eval_attribute
ON core_mdm.survivorship_evaluations(attribute_name);

CREATE INDEX IF NOT EXISTS idx_survivorship_eval_confidence
ON core_mdm.survivorship_evaluations(confidence_score DESC);

CREATE INDEX IF NOT EXISTS idx_survivorship_eval_metadata_gin
ON core_mdm.survivorship_evaluations
USING GIN(metadata);

--
-- ============================================================
-- SURVIVORSHIP RULES
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_survivorship_rules_status
ON core_mdm.survivorship_rules(status);

CREATE INDEX IF NOT EXISTS idx_survivorship_rules_priority
ON core_mdm.survivorship_rules(priority DESC);

CREATE INDEX IF NOT EXISTS idx_survivorship_rules_strategy
ON core_mdm.survivorship_rules(strategy);

CREATE INDEX IF NOT EXISTS idx_survivorship_rules_attribute
ON core_mdm.survivorship_rules(attribute_name);

--
-- ============================================================
-- VECTOR TABLES
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_embeddings_tenant
ON core_mdm.entity_embeddings(tenant_id);

CREATE INDEX IF NOT EXISTS idx_embeddings_entity
ON core_mdm.entity_embeddings(entity_id);

CREATE INDEX IF NOT EXISTS idx_embeddings_model
ON core_mdm.entity_embeddings(model_name);

CREATE INDEX IF NOT EXISTS idx_embeddings_created
ON core_mdm.entity_embeddings(created_at DESC);

--
-- pgvector similarity index
--

CREATE INDEX IF NOT EXISTS idx_embeddings_vector_cosine
ON core_mdm.entity_embeddings
USING ivfflat (
    embedding vector_cosine_ops
)
WITH (lists = 100);

--
-- ============================================================
-- EVENT STORE
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_outbox_events_unpublished
ON event_store.outbox_events(
    published,
    created_at
);

CREATE INDEX IF NOT EXISTS idx_outbox_events_topic
ON event_store.outbox_events(topic_name);

CREATE INDEX IF NOT EXISTS idx_outbox_events_aggregate
ON event_store.outbox_events(
    aggregate_type,
    aggregate_id
);

CREATE INDEX IF NOT EXISTS idx_event_log_aggregate
ON event_store.event_log(
    aggregate_type,
    aggregate_id
);

CREATE INDEX IF NOT EXISTS idx_event_log_created
ON event_store.event_log(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_event_log_payload_gin
ON event_store.event_log
USING GIN(payload);

--
-- ============================================================
-- AUDIT TABLES
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_audit_logs_tenant
ON audit.audit_logs(tenant_id);

CREATE INDEX IF NOT EXISTS idx_audit_logs_entity
ON audit.audit_logs(entity_id);

CREATE INDEX IF NOT EXISTS idx_audit_logs_actor
ON audit.audit_logs(actor_id);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created
ON audit.audit_logs(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_logs_action
ON audit.audit_logs(action);

CREATE INDEX IF NOT EXISTS idx_audit_logs_changes_gin
ON audit.audit_logs
USING GIN(changes);

--
-- ============================================================
-- LINEAGE
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_lineage_source
ON lineage.entity_lineage(source_entity_id);

CREATE INDEX IF NOT EXISTS idx_lineage_target
ON lineage.entity_lineage(target_entity_id);

CREATE INDEX IF NOT EXISTS idx_lineage_relationship
ON lineage.entity_lineage(relationship_type);

CREATE INDEX IF NOT EXISTS idx_lineage_created
ON lineage.entity_lineage(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_lineage_metadata_gin
ON lineage.entity_lineage
USING GIN(metadata);

--
-- ============================================================
-- PARTIAL INDEXES
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_active_entities
ON core_mdm.entities(entity_id)
WHERE status = 'Active';

CREATE INDEX IF NOT EXISTS idx_active_golden_records
ON core_mdm.golden_records(golden_record_id)
WHERE status = 'Active';

CREATE INDEX IF NOT EXISTS idx_pending_match_reviews
ON core_mdm.match_candidates(match_candidate_id)
WHERE requires_human_review = TRUE;

CREATE INDEX IF NOT EXISTS idx_active_survivorship_rules
ON core_mdm.survivorship_rules(rule_id)
WHERE status = 'Active';

--
-- ============================================================
-- COMPOSITE ANALYTICS INDEXES
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_entities_tenant_status_type
ON core_mdm.entities(
    tenant_id,
    status,
    entity_type_id
);

CREATE INDEX IF NOT EXISTS idx_golden_records_tenant_status
ON core_mdm.golden_records(
    tenant_id,
    status
);

CREATE INDEX IF NOT EXISTS idx_match_candidates_request_review
ON core_mdm.match_candidates(
    request_id,
    requires_human_review
);

CREATE INDEX IF NOT EXISTS idx_survivorship_execution_tenant_created
ON core_mdm.survivorship_executions(
    tenant_id,
    created_at DESC
);

--
-- ============================================================
-- COMMENTS
-- ============================================================
--

COMMENT ON INDEX idx_entities_search_vector
IS 'GIN full-text search index for entities';

COMMENT ON INDEX idx_embeddings_vector_cosine
IS 'pgvector cosine similarity ANN index';

COMMENT ON INDEX idx_outbox_events_unpublished
IS 'Optimized polling for unpublished Kafka events';

COMMENT ON INDEX idx_pending_match_reviews
IS 'Human review queue acceleration';

COMMENT ON INDEX idx_active_survivorship_rules
IS 'Fast active-rule lookup for survivorship engine';