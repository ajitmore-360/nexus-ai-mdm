-- ============================================================
-- Async ingest job progress tracking
--
-- Adds per-chunk progress counters so the async worker can
-- update job state incrementally without rewriting entity_ids
-- for millions of records.
-- ============================================================

ALTER TABLE ingest.ingest_jobs
    ADD COLUMN IF NOT EXISTS chunks_total  INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS chunks_done   INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS chunk_size    INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN ingest.ingest_jobs.chunks_total IS
    'Total chunks queued for async processing (0 for synchronous batches).';
COMMENT ON COLUMN ingest.ingest_jobs.chunks_done IS
    'Chunks that have finished processing (success or failure).';
COMMENT ON COLUMN ingest.ingest_jobs.chunk_size IS
    'Number of records per chunk used when splitting a large CSV upload.';
