--
-- ============================================
-- EVENT LOG PARTITIONS
-- ============================================
--

CREATE TABLE IF NOT EXISTS event_store.event_log_2026_01
PARTITION OF event_store.event_log
FOR VALUES FROM ('2026-01-01')
TO ('2026-02-01');

--
-- ============================================
-- PARTITION INDEXES
-- ============================================
--

CREATE INDEX IF NOT EXISTS idx_event_log_2026_01_tenant
ON event_store.event_log_2026_01(tenant_id);

CREATE INDEX IF NOT EXISTS idx_event_log_2026_01_aggregate
ON event_store.event_log_2026_01(
    aggregate_type,
    aggregate_id
);

CREATE INDEX IF NOT EXISTS idx_event_log_2026_01_event_type
ON event_store.event_log_2026_01(event_type);

CREATE INDEX IF NOT EXISTS idx_event_log_2026_01_created
ON event_store.event_log_2026_01(created_at);

CREATE INDEX IF NOT EXISTS idx_event_log_2026_01_payload
ON event_store.event_log_2026_01
USING GIN(payload);