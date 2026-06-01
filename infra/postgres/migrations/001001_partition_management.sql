CREATE OR REPLACE FUNCTION
event_store.create_monthly_partition(
    partition_date DATE
)
RETURNS void
LANGUAGE plpgsql
AS
$$
DECLARE
    partition_name TEXT;
BEGIN

    partition_name :=
        'event_log_' ||
        to_char(
            partition_date,
            'YYYY_MM'
        );

    EXECUTE format(
        '
        CREATE TABLE IF NOT EXISTS
        event_store.%I
        PARTITION OF
        event_store.event_log
        FOR VALUES FROM (%L)
        TO (%L)
        ',
        partition_name,
        partition_date,
        partition_date
            + interval '1 month'
    );

END;
$$;