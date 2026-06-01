CREATE TABLE IF NOT EXISTS audit.audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL,
    old_data JSONB,
    new_data JSONB,
    changed_by UUID,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    correlation_id UUID,
    metadata JSONB DEFAULT '{}'::JSONB
);

CREATE OR REPLACE FUNCTION audit.audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_record_id UUID;
BEGIN
    v_record_id := COALESCE(
        NEW.entity_id,
        OLD.entity_id
    );

    INSERT INTO audit.audit_log (
        tenant_id,
        table_name,
        record_id,
        operation,
        old_data,
        new_data,
        changed_by
    )
    VALUES (
        COALESCE(NEW.tenant_id, OLD.tenant_id),
        TG_TABLE_NAME,
        v_record_id,
        TG_OP,
        to_jsonb(OLD),
        to_jsonb(NEW),
        app_context.current_user_id()
    );

    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_audit_entities
AFTER INSERT OR UPDATE OR DELETE
ON core_mdm.entities
FOR EACH ROW
EXECUTE FUNCTION audit.audit_trigger();

