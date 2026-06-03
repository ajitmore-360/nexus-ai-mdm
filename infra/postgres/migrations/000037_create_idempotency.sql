CREATE SCHEMA IF NOT EXISTS platform;

CREATE TABLE IF NOT EXISTS platform.idempotency_keys
(
    idempotency_key VARCHAR(255)
        PRIMARY KEY,

    created_at TIMESTAMPTZ
        NOT NULL DEFAULT NOW()
);