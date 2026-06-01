CREATE OR REPLACE FUNCTION event_store.create_monthly_partition(
    parent_table TEXT,
    partition_date DATE
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    partition_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    start_date := date_trunc('month', partition_date)::DATE;
    end_date := (start_date + INTERVAL '1 month')::DATE;

    partition_name := parent_table || '_' ||
        to_char(start_date, 'YYYY_MM');

    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS event_store.%I
         PARTITION OF event_store.%I
         FOR VALUES FROM (%L) TO (%L)',
        partition_name,
        parent_table,
        start_date,
        end_date
    );
END;
$$;