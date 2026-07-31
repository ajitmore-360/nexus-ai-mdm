-- =============================================================================
-- 00_bootstrap.sql — Run this BEFORE any numbered migration.
--
-- Creates all required PostgreSQL extensions and application schemas.
-- Must run as a superuser (or a role with CREATE EXTENSION privileges).
--
-- Usage:
--   psql -U postgres -d nexus_mdm -f 00_bootstrap.sql
-- =============================================================================

-- ── Extensions ────────────────────────────────────────────────────────────────
-- pgcrypto: crypt() / gen_salt() used by auth migrations for password hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- citext: case-insensitive text type used for emails and tenant codes
CREATE EXTENSION IF NOT EXISTS citext;

-- pgvector: VECTOR column type and ANN indexes used by AI embedding tables
CREATE EXTENSION IF NOT EXISTS vector;

-- pg_trgm: trigram-based fuzzy search, used by matching engine blocking
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- uuid-ossp: gen_random_uuid() — most migrations use the built-in pg 13+ version,
-- but this ensures compatibility with older PostgreSQL 12 installations
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- pg_cron (optional): used by retention and materialized-view refresh schedules.
-- Requires pg_cron to be installed in shared_preload_libraries first.
-- The migrations that call cron.schedule() are wrapped in IF EXISTS guards,
-- so the schema still applies cleanly without pg_cron.
-- CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ── Application schemas ───────────────────────────────────────────────────────
-- These must exist before migration 0002 runs.

-- Master data domain
CREATE SCHEMA IF NOT EXISTS core_mdm;

-- AI / ML tables (embeddings, suggestions, anomalies, steward feedback)
CREATE SCHEMA IF NOT EXISTS ai;

-- Transactional outbox for reliable Kafka publishing
CREATE SCHEMA IF NOT EXISTS event_store;

-- OPA / Rego governance policy rules
CREATE SCHEMA IF NOT EXISTS governance;

-- GDPR audit trail (separate from operational audit)
CREATE SCHEMA IF NOT EXISTS audit;

-- Platform infrastructure (notifications, distribution, licensing)
CREATE SCHEMA IF NOT EXISTS platform;

-- Ingest service jobs (created by ingest-service migrations)
CREATE SCHEMA IF NOT EXISTS ingest;

-- Data lineage graph (provenance of entity merges, enrichment)
CREATE SCHEMA IF NOT EXISTS lineage;

-- Notification delivery (webhooks, delivery log)
CREATE SCHEMA IF NOT EXISTS notifications;
