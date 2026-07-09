-- Migration 002015: PostgreSQL NOTIFY trigger for real-time WebSocket push
--
-- Problem: when a record is created/updated by any service (mdm-core, ingest,
-- match engine, etc.), the API gateway's WebSocket clients need to be notified
-- immediately â€” not just the originating service instance.
--
-- Solution: a NOTIFY trigger on core MDM tables fires a pg_notify payload that
-- the API gateway can subscribe to via LISTEN. The gateway then fans the message
-- out to the appropriate tenant's WebSocket sessions via WsManager.
--
-- Channel conventions:
--   AZILE_entity_changes   â€” entity create/update/delete events
--   AZILE_review_events    â€” new match candidates added to the review queue
--   AZILE_inbox_events     â€” new rows in notifications.inbox (per-user toasts)
--
-- Payload schema (JSON):
--   {
--     "tenant_id":     "uuid",
--     "event_type":    "entity.created" | "entity.updated" | ... ,
--     "resource_id":   "uuid",    -- entity_id, review_id, notification_id, etc.
--     "resource_type": "entity" | "review" | "notification",
--     "ts":            "ISO-8601"
--   }
--
-- Note: pg_notify payload is limited to 8 000 bytes.  We send only IDs, never
-- full payloads, so the WebSocket client fetches fresh data via the REST API.

-- â”€â”€ Helper: generic NOTIFY trigger function â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

CREATE OR REPLACE FUNCTION core_mdm.notify_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_channel     TEXT;
    v_event_type  TEXT;
    v_resource_id TEXT;
    v_tenant_id   TEXT;
    v_payload     TEXT;
BEGIN
    -- Resolve per-table channel and event_type.
    CASE TG_TABLE_NAME
        WHEN 'entities' THEN
            v_channel      := 'AZILE_entity_changes';
            v_resource_id  := COALESCE(NEW.entity_id, OLD.entity_id)::TEXT;
            v_tenant_id    := COALESCE(NEW.tenant_id, OLD.tenant_id)::TEXT;
            v_event_type   := CASE TG_OP
                                  WHEN 'INSERT' THEN 'entity.created'
                                  WHEN 'UPDATE' THEN 'entity.updated'
                                  WHEN 'DELETE' THEN 'entity.deleted'
                                  ELSE 'entity.changed'
                              END;

        WHEN 'match_review_queue' THEN
            v_channel      := 'AZILE_review_events';
            v_resource_id  := COALESCE(NEW.review_id, OLD.review_id)::TEXT;
            v_tenant_id    := COALESCE(NEW.tenant_id, OLD.tenant_id)::TEXT;
            v_event_type   := CASE TG_OP
                                  WHEN 'INSERT' THEN 'review.created'
                                  WHEN 'UPDATE' THEN 'review.updated'
                                  ELSE 'review.changed'
                              END;

        WHEN 'inbox' THEN
            v_channel      := 'AZILE_inbox_events';
            v_resource_id  := COALESCE(NEW.notification_id, OLD.notification_id)::TEXT;
            v_tenant_id    := COALESCE(NEW.tenant_id, OLD.tenant_id)::TEXT;
            v_event_type   := CASE TG_OP
                                  WHEN 'INSERT' THEN 'notification.created'
                                  WHEN 'UPDATE' THEN 'notification.updated'
                                  ELSE 'notification.changed'
                              END;

        ELSE
            -- Unknown table â€” no-op rather than erroring.
            RETURN COALESCE(NEW, OLD);
    END CASE;

    -- Build compact JSON payload (well under 8 000-byte pg_notify limit).
    v_payload := json_build_object(
        'tenant_id',     v_tenant_id,
        'event_type',    v_event_type,
        'resource_id',   v_resource_id,
        'resource_type', TG_TABLE_NAME,
        'ts',            NOW()
    )::TEXT;

    PERFORM pg_notify(v_channel, v_payload);

    RETURN COALESCE(NEW, OLD);
END;
$$;

-- â”€â”€ Entities table â€” AFTER INSERT / UPDATE / DELETE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

DROP TRIGGER IF EXISTS trg_notify_entity_change ON core_mdm.entities;

CREATE TRIGGER trg_notify_entity_change
    AFTER INSERT OR UPDATE OR DELETE
    ON core_mdm.entities
    FOR EACH ROW
    EXECUTE FUNCTION core_mdm.notify_change();

-- â”€â”€ Match review queue â€” AFTER INSERT / UPDATE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

DROP TRIGGER IF EXISTS trg_notify_review_change ON core_mdm.match_review_queue;

CREATE TRIGGER trg_notify_review_change
    AFTER INSERT OR UPDATE
    ON core_mdm.match_review_queue
    FOR EACH ROW
    EXECUTE FUNCTION core_mdm.notify_change();

-- â”€â”€ Notification inbox â€” AFTER INSERT / UPDATE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

DROP TRIGGER IF EXISTS trg_notify_inbox_change ON notifications.inbox;

CREATE TRIGGER trg_notify_inbox_change
    AFTER INSERT OR UPDATE
    ON notifications.inbox
    FOR EACH ROW
    EXECUTE FUNCTION core_mdm.notify_change();
