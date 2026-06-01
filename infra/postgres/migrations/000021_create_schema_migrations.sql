CREATE SCHEMA IF NOT EXISTS platform;

CREATE TABLE IF NOT EXISTS platform.schema_migrations (

    version BIGINT PRIMARY KEY,

    migration_name TEXT NOT NULL,

    checksum TEXT,

    executed_at TIMESTAMPTZ NOT NULL
        DEFAULT NOW(),

    execution_time_ms BIGINT,

    executed_by TEXT,

    success BOOLEAN NOT NULL
        DEFAULT TRUE
);