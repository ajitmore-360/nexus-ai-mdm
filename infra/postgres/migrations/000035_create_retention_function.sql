CREATE OR REPLACE FUNCTION event_store.cleanup_old_events(
    retention_months INTEGER DEFAULT 24
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    cutoff_date DATE;
BEGIN
    cutoff_date := (
        CURRENT_DATE
        - (retention_months || ' months')::INTERVAL
    )::DATE;

    DELETE FROM event_store.dead_letter_events
    WHERE created_at < cutoff_date;
END;
$$; 