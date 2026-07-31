-- Migration 0015: AI-generated suggestions pending user approval
-- ─────────────────────────────────────────────────────────────────────────────
-- Suggestions are always proposals — never auto-applied.
-- Each row holds what the LLM saw (safe_input) and what it proposed
-- (suggestion), keeping a full audit trail of the AI's reasoning.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.ai_suggestions (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID         NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    entity_id        UUID         REFERENCES core_mdm.entities(entity_id) ON DELETE CASCADE,
    entity_type      TEXT         NOT NULL DEFAULT '',

    -- What triggered this suggestion
    suggestion_type  TEXT         NOT NULL
        CHECK (suggestion_type IN ('address_parse', 'anomaly', 'enrichment')),

    -- Lifecycle
    status           TEXT         NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'rejected', 'applied')),

    -- What was sent to the LLM (PII-stripped snapshot, safe to store)
    safe_input       JSONB        NOT NULL DEFAULT '{}'::jsonb,

    -- What the LLM proposed: array of {field, proposed_value, rationale, confidence}
    suggestion       JSONB        NOT NULL DEFAULT '[]'::jsonb,

    -- Human-readable explanation returned by the LLM
    rationale        TEXT         NOT NULL DEFAULT '',

    -- Confidence score 0.0–1.0 (from LLM response or heuristic)
    confidence       NUMERIC(4,3) CHECK (confidence >= 0 AND confidence <= 1),

    -- Review audit
    reviewed_by      UUID,
    reviewed_at      TIMESTAMPTZ,
    applied_at       TIMESTAMPTZ,

    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_sug_tenant_entity
    ON core_mdm.ai_suggestions (tenant_id, entity_id);

CREATE INDEX IF NOT EXISTS idx_ai_sug_status
    ON core_mdm.ai_suggestions (tenant_id, status)
    WHERE status = 'pending';

-- RLS: each tenant sees only its own suggestions
ALTER TABLE core_mdm.ai_suggestions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'ai_suggestions'
          AND policyname = 'ai_suggestions_tenant_isolation'
    ) THEN
        CREATE POLICY ai_suggestions_tenant_isolation
            ON core_mdm.ai_suggestions
            USING (
                tenant_id = COALESCE(
                    current_setting('app.current_tenant', true)::uuid,
                    tenant_id
                )
            );
    END IF;
END $$;
