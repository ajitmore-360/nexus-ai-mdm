--
-- ============================================
-- EVENT STORE SCHEMA
-- ============================================
--

CREATE SCHEMA IF NOT EXISTS event_store;

--
-- ============================================
-- OUTBOX EVENTS
-- ============================================
--

CREATE TABLE IF NOT EXISTS event_store.outbox_events (

    event_id UUID PRIMARY KEY,

    tenant_id UUID NOT NULL,

    aggregate_type TEXT NOT NULL,

    aggregate_id UUID NOT NULL,

    event_type TEXT NOT NULL,

    event_version INTEGER NOT NULL DEFAULT 1,

    event_payload JSONB NOT NULL,

    event_metadata JSONB
        NOT NULL DEFAULT '{}'::JSONB,

    event_headers JSONB
        NOT NULL DEFAULT '{}'::JSONB,

    correlation_id UUID,

    causation_id UUID,

    trace_id VARCHAR(255),

    partition_key VARCHAR(255),

    topic_name TEXT NOT NULL,

    event_timestamp TIMESTAMPTZ
        NOT NULL DEFAULT NOW(),

    published BOOLEAN
        NOT NULL DEFAULT FALSE,

    published_at TIMESTAMPTZ,

    retry_count INTEGER
        NOT NULL DEFAULT 0,

    last_error TEXT,

    created_at TIMESTAMPTZ
        NOT NULL DEFAULT NOW()
);

--
-- ============================================
-- OUTBOX INDEXES
-- ============================================
--

CREATE INDEX IF NOT EXISTS idx_outbox_tenant
ON event_store.outbox_events(tenant_id);

CREATE INDEX IF NOT EXISTS idx_outbox_published
ON event_store.outbox_events(published);

CREATE INDEX IF NOT EXISTS idx_outbox_event_type
ON event_store.outbox_events(event_type);

CREATE INDEX IF NOT EXISTS idx_outbox_topic
ON event_store.outbox_events(topic_name);

CREATE INDEX IF NOT EXISTS idx_outbox_created_at
ON event_store.outbox_events(created_at);

CREATE INDEX IF NOT EXISTS idx_outbox_aggregate
ON event_store.outbox_events(
    aggregate_type,
    aggregate_id
);

CREATE INDEX IF NOT EXISTS idx_outbox_partition_key
ON event_store.outbox_events(partition_key);

--
-- ============================================
-- OUTBOX JSONB INDEXES
-- ============================================
--

CREATE INDEX IF NOT EXISTS idx_outbox_payload_gin
ON event_store.outbox_events
USING GIN(event_payload);

CREATE INDEX IF NOT EXISTS idx_outbox_metadata_gin
ON event_store.outbox_events
USING GIN(event_metadata);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_outbox_unpublished_created
ON event_store.outbox_events(
    published,
    created_at
)
WHERE published = FALSE;

--
-- ============================================
-- PARTITIONED EVENT LOG
-- ============================================
--

CREATE TABLE IF NOT EXISTS event_store.event_log (

    --
    -- Event identity
    --
    event_log_id UUID NOT NULL,

    tenant_id UUID NOT NULL,

    --
    -- Aggregate
    --
    aggregate_type VARCHAR(255)
        NOT NULL,

    aggregate_id UUID
        NOT NULL,

    --
    -- Event
    --
    event_type VARCHAR(255)
        NOT NULL,

    event_version INTEGER
        NOT NULL,

    --
    -- Payload
    --
    payload JSONB
        NOT NULL,

    metadata JSONB
        NOT NULL DEFAULT '{}'::JSONB,

    --
    -- Correlation
    --
    correlation_id UUID,

    causation_id UUID,

    --
    -- Audit
    --
    created_by UUID,

    --
    -- Event timestamp
    --
    created_at TIMESTAMPTZ
        NOT NULL DEFAULT NOW(),

    --
    -- Partition-safe PK
    --
    PRIMARY KEY (
        event_log_id,
        created_at
    )
)
PARTITION BY RANGE (created_at);

--
-- ============================================
-- EVENT LOG INDEXES
-- ============================================
--

CREATE INDEX IF NOT EXISTS idx_event_log_tenant
ON event_store.event_log(tenant_id);

CREATE INDEX IF NOT EXISTS idx_event_log_aggregate
ON event_store.event_log(
    aggregate_type,
    aggregate_id
);

CREATE INDEX IF NOT EXISTS idx_event_log_event_type
ON event_store.event_log(event_type);

CREATE INDEX IF NOT EXISTS idx_event_log_created
ON event_store.event_log(created_at);

CREATE INDEX IF NOT EXISTS idx_event_log_payload
ON event_store.event_log
USING GIN(payload);

CREATE INDEX IF NOT EXISTS idx_event_log_metadata
ON event_store.event_log
USING GIN(metadata);

--
-- ============================================
-- DEAD LETTER QUEUE
-- ============================================
--

CREATE TABLE IF NOT EXISTS event_store.dead_letter_events (

    dead_letter_id UUID PRIMARY KEY,

    original_event_id UUID,

    tenant_id UUID,

    topic_name VARCHAR(255),

    payload JSONB,

    error_message TEXT,

    retry_attempts INTEGER
        DEFAULT 0,

    failed_at TIMESTAMPTZ
        NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dead_letter_tenant
ON event_store.dead_letter_events(tenant_id);

CREATE INDEX IF NOT EXISTS idx_dead_letter_failed
ON event_store.dead_letter_events(failed_at);

--
-- ============================================
-- CONSUMER OFFSETS
-- ============================================
--

CREATE TABLE IF NOT EXISTS event_store.consumer_offsets (

    consumer_group VARCHAR(255)
        NOT NULL,

    topic_name VARCHAR(255)
        NOT NULL,

    partition_id INTEGER
        NOT NULL,

    current_offset BIGINT
        NOT NULL,

    updated_at TIMESTAMPTZ
        NOT NULL DEFAULT NOW(),

    PRIMARY KEY (
        consumer_group,
        topic_name,
        partition_id
    )
);

--
-- ============================================
-- COMMENTS
-- ============================================
--

COMMENT ON TABLE event_store.outbox_events
IS 'Transactional outbox table for Kafka/NATS publishing';

COMMENT ON TABLE event_store.event_log
IS 'Immutable partitioned event sourcing log';

COMMENT ON TABLE event_store.dead_letter_events
IS 'Dead letter queue for failed event publishing';

COMMENT ON TABLE event_store.consumer_offsets
IS 'Consumer offset tracking';

--
-- ============================================
-- RLS and POLICY
-- ============================================
--
ALTER TABLE event_store.outbox_events
ENABLE ROW LEVEL SECURITY;

ALTER TABLE event_store.outbox_events
ADD CONSTRAINT chk_retry_count
CHECK (retry_count >= 0);

CREATE POLICY tenant_isolation_policy
ON event_store.outbox_events
USING (
    tenant_id =
    current_setting('app.current_tenant')::uuid
);
