--
-- CRITICAL:
-- POLLER INDEX
--

CREATE INDEX CONCURRENTLY
IF NOT EXISTS idx_outbox_polling
ON event_store.outbox_events
(
    published,
    retry_count,
    created_at
)
WHERE published = FALSE;

--
-- TENANT + POLLING
--

CREATE INDEX CONCURRENTLY
IF NOT EXISTS idx_outbox_tenant_polling
ON event_store.outbox_events
(
    tenant_id,
    published,
    created_at
)
WHERE published = FALSE;

--
-- DLQ OPERATIONS
--

CREATE INDEX CONCURRENTLY
IF NOT EXISTS idx_outbox_failed
ON event_store.outbox_events
(
    retry_count,
    created_at
)
WHERE retry_count > 0;

--
-- EVENT LOOKUPS
--

CREATE INDEX CONCURRENTLY
IF NOT EXISTS idx_outbox_aggregate_lookup
ON event_store.outbox_events
(
    tenant_id,
    aggregate_type,
    aggregate_id,
    created_at DESC
);

--
-- IDEMPOTENCY
--

CREATE UNIQUE INDEX CONCURRENTLY
IF NOT EXISTS idx_outbox_unique_event
ON event_store.outbox_events
(
    tenant_id,
    event_id
);