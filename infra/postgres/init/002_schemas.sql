--
-- =========================================================
-- Nexus MDM Platform
-- Production Schema Initialization
-- File: 002_schemas.sql
-- =========================================================
--

BEGIN;

--
-- =========================================================
-- CORE SCHEMAS
-- =========================================================
--

CREATE SCHEMA IF NOT EXISTS core_mdm;
CREATE SCHEMA IF NOT EXISTS event_store;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS lineage;
CREATE SCHEMA IF NOT EXISTS ai;
CREATE SCHEMA IF NOT EXISTS governance;
CREATE SCHEMA IF NOT EXISTS platform;
CREATE SCHEMA IF NOT EXISTS app_context;

--
-- =========================================================
-- COMPATIBILITY SCHEMA
-- =========================================================
-- Some migrations incorrectly reference `core.tenants`
-- instead of `core_mdm.tenants`.
--
-- We create compatibility schema now to prevent failures.
-- Later you may replace with views/synonyms if desired.
-- =========================================================
--

CREATE SCHEMA IF NOT EXISTS core;

--
-- =========================================================
-- SCHEMA OWNERSHIP
-- =========================================================
--

ALTER SCHEMA core_mdm OWNER TO nexus_migration;
ALTER SCHEMA event_store OWNER TO nexus_migration;
ALTER SCHEMA audit OWNER TO nexus_migration;
ALTER SCHEMA lineage OWNER TO nexus_migration;
ALTER SCHEMA ai OWNER TO nexus_migration;
ALTER SCHEMA governance OWNER TO nexus_migration;
ALTER SCHEMA platform OWNER TO nexus_migration;
ALTER SCHEMA app_context OWNER TO nexus_migration;
ALTER SCHEMA core OWNER TO nexus_migration;

--
-- =========================================================
-- REVOKE PUBLIC ACCESS
-- =========================================================
--

REVOKE ALL ON SCHEMA core_mdm FROM PUBLIC;
REVOKE ALL ON SCHEMA event_store FROM PUBLIC;
REVOKE ALL ON SCHEMA audit FROM PUBLIC;
REVOKE ALL ON SCHEMA lineage FROM PUBLIC;
REVOKE ALL ON SCHEMA ai FROM PUBLIC;
REVOKE ALL ON SCHEMA governance FROM PUBLIC;
REVOKE ALL ON SCHEMA platform FROM PUBLIC;
REVOKE ALL ON SCHEMA app_context FROM PUBLIC;
REVOKE ALL ON SCHEMA core FROM PUBLIC;

--
-- =========================================================
-- APPLICATION ROLE ACCESS
-- =========================================================
--

GRANT USAGE ON SCHEMA core_mdm TO nexus_app;
GRANT USAGE ON SCHEMA event_store TO nexus_app;
GRANT USAGE ON SCHEMA audit TO nexus_app;
GRANT USAGE ON SCHEMA lineage TO nexus_app;
GRANT USAGE ON SCHEMA ai TO nexus_app;
GRANT USAGE ON SCHEMA governance TO nexus_app;
GRANT USAGE ON SCHEMA platform TO nexus_app;
GRANT USAGE ON SCHEMA app_context TO nexus_app;
GRANT USAGE ON SCHEMA core TO nexus_app;

--
-- =========================================================
-- READONLY ACCESS
-- =========================================================
--

GRANT USAGE ON SCHEMA core_mdm TO nexus_readonly;
GRANT USAGE ON SCHEMA audit TO nexus_readonly;
GRANT USAGE ON SCHEMA lineage TO nexus_readonly;
GRANT USAGE ON SCHEMA platform TO nexus_readonly;

--
-- =========================================================
-- MIGRATION ACCESS
-- =========================================================
--

GRANT ALL ON SCHEMA core_mdm TO nexus_migration;
GRANT ALL ON SCHEMA event_store TO nexus_migration;
GRANT ALL ON SCHEMA audit TO nexus_migration;
GRANT ALL ON SCHEMA lineage TO nexus_migration;
GRANT ALL ON SCHEMA ai TO nexus_migration;
GRANT ALL ON SCHEMA governance TO nexus_migration;
GRANT ALL ON SCHEMA platform TO nexus_migration;
GRANT ALL ON SCHEMA app_context TO nexus_migration;
GRANT ALL ON SCHEMA core TO nexus_migration;

--
-- =========================================================
-- SEARCH PATHS
-- =========================================================
--

ALTER ROLE nexus_app
SET search_path =
    core_mdm,
    event_store,
    audit,
    lineage,
    ai,
    governance,
    app_context,
    platform,
    public;

ALTER ROLE nexus_readonly
SET search_path =
    core_mdm,
    audit,
    lineage,
    platform,
    public;

ALTER ROLE nexus_migration
SET search_path =
    core_mdm,
    event_store,
    audit,
    lineage,
    ai,
    governance,
    app_context,
    platform,
    public;

--
-- =========================================================
-- COMMENTS
-- =========================================================
--

COMMENT ON SCHEMA core_mdm
IS 'Primary multi-tenant master data management schema';

COMMENT ON SCHEMA event_store
IS 'Event sourcing, outbox, and event log schema';

COMMENT ON SCHEMA audit
IS 'Audit trail and compliance schema';

COMMENT ON SCHEMA lineage
IS 'Entity lineage and relationship tracking schema';

COMMENT ON SCHEMA ai
IS 'AI, embeddings, vector search, and RAG schema';

COMMENT ON SCHEMA governance
IS 'Governance, policy, and compliance schema';

COMMENT ON SCHEMA platform
IS 'Platform operational metadata schema';

COMMENT ON SCHEMA app_context
IS 'Tenant/user session context functions';

COMMENT ON SCHEMA core
IS 'Backward compatibility schema for legacy migrations';

COMMIT;