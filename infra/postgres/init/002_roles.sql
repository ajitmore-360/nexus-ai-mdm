--
-- =========================================================
-- Azile MDM Platform
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

-- â”€â”€ Application role â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'azile_app') THEN
        CREATE ROLE azile_app
            LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION INHERIT;
    END IF;
END $$;

-- â”€â”€ Read-only analytics role â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'azile_readonly') THEN
        CREATE ROLE azile_readonly
            LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION INHERIT;
    END IF;
END $$;

-- â”€â”€ Migration / DDL management role â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'azile_migration') THEN
        CREATE ROLE azile_migration
            LOGIN NOSUPERUSER CREATEDB CREATEROLE NOREPLICATION INHERIT;
    END IF;
END $$;

-- â”€â”€ Security settings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

ALTER ROLE azile_app       SET row_security                        = on;
ALTER ROLE azile_app       SET default_transaction_isolation       = 'read committed';
ALTER ROLE azile_app       SET idle_in_transaction_session_timeout = '5min';
ALTER ROLE azile_app       SET application_name                    = 'azile-mdm-app';

ALTER ROLE azile_readonly  SET default_transaction_read_only       = on;
ALTER ROLE azile_readonly  SET idle_in_transaction_session_timeout = '5min';
ALTER ROLE azile_readonly  SET application_name                    = 'azile-mdm-readonly';

ALTER ROLE azile_migration SET lock_timeout                        = '30s';
ALTER ROLE azile_migration SET statement_timeout                   = '30min';
ALTER ROLE azile_migration SET application_name                    = 'azile-mdm-migrations';

-- â”€â”€ Database connect privileges â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

GRANT CONNECT ON DATABASE azile_mdm TO azile_app;
GRANT CONNECT ON DATABASE azile_mdm TO azile_readonly;
GRANT CONNECT ON DATABASE azile_mdm TO azile_migration;

-- â”€â”€ Role comments â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

COMMENT ON ROLE azile_app       IS 'Primary runtime role for Azile MDM platform';
COMMENT ON ROLE azile_readonly  IS 'Read-only analytics and BI role';
COMMENT ON ROLE azile_migration IS 'Schema migration and DDL management role';

COMMIT;
