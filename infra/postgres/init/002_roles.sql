--
-- =========================================================
-- Nexus MDM Platform
-- Role Initialization (no schema references)
-- File: 002_roles.sql
-- =========================================================
-- IMPORTANT: This file must NOT reference any schema names.
-- Schema creation happens in 003_schemas.sql.
-- Default privileges are granted in 004_default_privileges.sql
-- after schemas exist.
-- =========================================================
--

BEGIN;

-- ── Application role ──────────────────────────────────────────────────────

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nexus_app') THEN
        CREATE ROLE nexus_app
            LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION INHERIT;
    END IF;
END $$;

-- ── Read-only analytics role ───────────────────────────────────────────────

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nexus_readonly') THEN
        CREATE ROLE nexus_readonly
            LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION INHERIT;
    END IF;
END $$;

-- ── Migration / DDL management role ───────────────────────────────────────

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nexus_migration') THEN
        CREATE ROLE nexus_migration
            LOGIN NOSUPERUSER CREATEDB CREATEROLE NOREPLICATION INHERIT;
    END IF;
END $$;

-- ── Security settings ──────────────────────────────────────────────────────

ALTER ROLE nexus_app       SET row_security                        = on;
ALTER ROLE nexus_app       SET default_transaction_isolation       = 'read committed';
ALTER ROLE nexus_app       SET idle_in_transaction_session_timeout = '5min';
ALTER ROLE nexus_app       SET application_name                    = 'nexus-mdm-app';

ALTER ROLE nexus_readonly  SET default_transaction_read_only       = on;
ALTER ROLE nexus_readonly  SET idle_in_transaction_session_timeout = '5min';
ALTER ROLE nexus_readonly  SET application_name                    = 'nexus-mdm-readonly';

ALTER ROLE nexus_migration SET lock_timeout                        = '30s';
ALTER ROLE nexus_migration SET statement_timeout                   = '30min';
ALTER ROLE nexus_migration SET application_name                    = 'nexus-mdm-migrations';

-- ── Database connect privileges ────────────────────────────────────────────

GRANT CONNECT ON DATABASE nexus_mdm TO nexus_app;
GRANT CONNECT ON DATABASE nexus_mdm TO nexus_readonly;
GRANT CONNECT ON DATABASE nexus_mdm TO nexus_migration;

-- ── Role comments ──────────────────────────────────────────────────────────

COMMENT ON ROLE nexus_app       IS 'Primary runtime role for Nexus MDM platform';
COMMENT ON ROLE nexus_readonly  IS 'Read-only analytics and BI role';
COMMENT ON ROLE nexus_migration IS 'Schema migration and DDL management role';

COMMIT;
