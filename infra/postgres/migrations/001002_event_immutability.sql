CREATE OR REPLACE FUNCTION
event_store.prevent_event_update()
RETURNS trigger
LANGUAGE plpgsql
AS
$$
BEGIN
    RAISE EXCEPTION
    'event_log is immutable';
END;
$$;

CREATE TRIGGER trg_prevent_event_update
BEFORE UPDATE
ON event_store.event_log
FOR EACH ROW
EXECUTE FUNCTION
event_store.prevent_event_update();