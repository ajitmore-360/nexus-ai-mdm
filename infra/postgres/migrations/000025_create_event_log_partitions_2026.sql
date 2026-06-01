CREATE TABLE IF NOT EXISTS event_store.event_log_2026_02
PARTITION OF event_store.event_log
FOR VALUES FROM ('2026-02-01')
TO ('2026-03-01');