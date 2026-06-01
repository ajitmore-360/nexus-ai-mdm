CREATE OR REPLACE FUNCTION event_store.prevent_event_log_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'event_log is immutable';
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_event_log_mutation
ON event_store.event_log;

CREATE TRIGGER trg_prevent_event_log_mutation
BEFORE UPDATE OR DELETE
ON event_store.event_log
FOR EACH ROW
EXECUTE FUNCTION event_store.prevent_event_log_mutation();
