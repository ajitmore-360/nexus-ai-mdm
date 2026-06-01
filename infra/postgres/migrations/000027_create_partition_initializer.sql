CREATE OR REPLACE FUNCTION event_store.ensure_future_partitions(
    months_ahead INTEGER DEFAULT 6
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    current_month DATE;
    i INTEGER;
BEGIN
    FOR i IN 0..months_ahead LOOP
        current_month := (
            date_trunc('month', CURRENT_DATE)
            + (i || ' month')::INTERVAL
        )::DATE;

        PERFORM event_store.create_monthly_partition(
            'mdm_events',
            current_month
        );

        PERFORM event_store.create_monthly_partition(
            'event_log',
            current_month
        );

        PERFORM event_store.create_monthly_partition(
            'outbox_events',
            current_month
        );

        PERFORM event_store.create_monthly_partition(
            'dead_letter_events',
            current_month
        );
    END LOOP;
END;
$$;