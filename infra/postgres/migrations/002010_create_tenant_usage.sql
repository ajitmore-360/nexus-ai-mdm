-- ============================================================================
-- Migration 002010: Tenant Usage Tracking
-- Real-time usage snapshot (tenant_usage) + monthly billing rollup (usage_monthly).
-- tenant_usage is updated by mdm-core on entity/steward changes and nightly recompute.
-- usage_monthly is snapshotted at month-end for billing records.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- Table: tenant_usage — live usage snapshot per tenant
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.tenant_usage (
    tenant_id               UUID    PRIMARY KEY
                                    REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,

    -- MDM limits (compared against tenant_licenses)
    golden_records          BIGINT  NOT NULL DEFAULT 0,
    active_domains          INTEGER NOT NULL DEFAULT 0,    -- distinct entity_type_codes in use
    active_stewards         INTEGER NOT NULL DEFAULT 0,    -- users with role steward/admin

    -- Activity counters (current calendar month, reset monthly)
    matches_this_month      BIGINT  NOT NULL DEFAULT 0,
    merges_this_month       BIGINT  NOT NULL DEFAULT 0,
    ingest_records_month    BIGINT  NOT NULL DEFAULT 0,
    api_calls_today         BIGINT  NOT NULL DEFAULT 0,

    -- Timestamps
    last_computed           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE core_mdm.tenant_usage IS
'Live usage snapshot — compared against tenant_licenses limits for quota enforcement.
 golden_records and active_domains/stewards are hard-limit dimensions.
 monthly counters are informational (used for billing dashboards).';

-- ─────────────────────────────────────────────────────────────────────────────
-- Table: usage_monthly — immutable billing rollup per month
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.usage_monthly (
    id                      UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               UUID    NOT NULL REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,

    -- e.g. '2026-06'
    year_month              TEXT    NOT NULL,

    -- Peak values within the billing period
    golden_records_peak     BIGINT  NOT NULL DEFAULT 0,
    active_domains_peak     INTEGER NOT NULL DEFAULT 0,
    active_stewards_peak    INTEGER NOT NULL DEFAULT 0,

    -- Cumulative totals for the month
    matches_total           BIGINT  NOT NULL DEFAULT 0,
    merges_total            BIGINT  NOT NULL DEFAULT 0,
    ingest_records_total    BIGINT  NOT NULL DEFAULT 0,

    -- Overage flags (set when tenant exceeded tier limits at any point this month)
    exceeded_records        BOOLEAN NOT NULL DEFAULT FALSE,
    exceeded_domains        BOOLEAN NOT NULL DEFAULT FALSE,
    exceeded_stewards       BOOLEAN NOT NULL DEFAULT FALSE,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(tenant_id, year_month)
);

CREATE INDEX IF NOT EXISTS idx_usage_monthly_tenant    ON core_mdm.usage_monthly(tenant_id);
CREATE INDEX IF NOT EXISTS idx_usage_monthly_yearmonth ON core_mdm.usage_monthly(year_month);

COMMENT ON TABLE core_mdm.usage_monthly IS
'Immutable monthly billing snapshots. Created/updated by the nightly usage recompute job
 or by the UsageService at month-end. Used for invoicing and overage detection.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Function: recompute_tenant_usage(p_tenant_id UUID)
-- Recalculates golden_records, active_domains, and active_stewards from live data.
-- Called nightly via pg_cron and on-demand by LicenseService.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION core_mdm.recompute_tenant_usage(p_tenant_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_records  BIGINT;
    v_domains  INTEGER;
    v_stewards INTEGER;
BEGIN
    -- Count active golden records
    SELECT COUNT(*) INTO v_records
    FROM   core_mdm.golden_records
    WHERE  tenant_id = p_tenant_id
      AND  status NOT IN ('Deleted', 'Archived');

    -- Count distinct entity type codes active
    SELECT COUNT(DISTINCT entity_type_code) INTO v_domains
    FROM   core_mdm.entities
    WHERE  tenant_id = p_tenant_id
      AND  status NOT IN ('Deleted', 'Archived', 'SoftDeleted');

    -- Count stewards + admins (users who can take write actions)
    SELECT COUNT(*) INTO v_stewards
    FROM   core_mdm.tenant_users tu
    WHERE  tu.tenant_id = p_tenant_id
      AND  tu.role IN ('steward', 'admin')
      AND  tu.is_active = TRUE;

    INSERT INTO core_mdm.tenant_usage (
        tenant_id, golden_records, active_domains, active_stewards, last_computed, updated_at
    ) VALUES (
        p_tenant_id, v_records, v_domains, v_stewards, NOW(), NOW()
    )
    ON CONFLICT (tenant_id) DO UPDATE SET
        golden_records  = EXCLUDED.golden_records,
        active_domains  = EXCLUDED.active_domains,
        active_stewards = EXCLUDED.active_stewards,
        last_computed   = EXCLUDED.last_computed,
        updated_at      = EXCLUDED.updated_at;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Function: snapshot_monthly_usage(p_year_month TEXT)
-- Snapshots current tenant_usage into usage_monthly for billing.
-- Called at month-end by pg_cron: '0 0 1 * *'
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION core_mdm.snapshot_monthly_usage(p_year_month TEXT)
RETURNS INTEGER   -- number of tenants snapshotted
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER := 0;
    lim     RECORD;
BEGIN
    FOR lim IN
        SELECT u.tenant_id,
               u.golden_records,
               u.active_domains,
               u.active_stewards,
               u.matches_this_month,
               u.merges_this_month,
               u.ingest_records_month,
               l.max_records,
               l.max_domains,
               l.max_stewards
        FROM   core_mdm.tenant_usage u
        LEFT JOIN core_mdm.tenant_licenses l USING (tenant_id)
    LOOP
        INSERT INTO core_mdm.usage_monthly (
            tenant_id, year_month,
            golden_records_peak, active_domains_peak, active_stewards_peak,
            matches_total, merges_total, ingest_records_total,
            exceeded_records, exceeded_domains, exceeded_stewards
        ) VALUES (
            lim.tenant_id, p_year_month,
            lim.golden_records, lim.active_domains, lim.active_stewards,
            lim.matches_this_month, lim.merges_this_month, lim.ingest_records_month,
            -- exceeded = over limit (ignore -1 = unlimited)
            (lim.max_records  <> -1 AND lim.golden_records  > lim.max_records),
            (lim.max_domains  <> -1 AND lim.active_domains  > lim.max_domains),
            (lim.max_stewards <> -1 AND lim.active_stewards > lim.max_stewards)
        )
        ON CONFLICT (tenant_id, year_month) DO UPDATE SET
            golden_records_peak  = GREATEST(usage_monthly.golden_records_peak, EXCLUDED.golden_records_peak),
            active_domains_peak  = GREATEST(usage_monthly.active_domains_peak, EXCLUDED.active_domains_peak),
            active_stewards_peak = GREATEST(usage_monthly.active_stewards_peak, EXCLUDED.active_stewards_peak),
            matches_total        = EXCLUDED.matches_total,
            merges_total         = EXCLUDED.merges_total,
            ingest_records_total = EXCLUDED.ingest_records_total,
            exceeded_records     = EXCLUDED.exceeded_records,
            exceeded_domains     = EXCLUDED.exceeded_domains,
            exceeded_stewards    = EXCLUDED.exceeded_stewards,
            updated_at           = NOW();

        v_count := v_count + 1;
    END LOOP;

    RETURN v_count;
END;
$$;
