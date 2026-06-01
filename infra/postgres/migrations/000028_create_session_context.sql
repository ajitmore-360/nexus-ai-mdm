CREATE OR REPLACE FUNCTION app_context.set_tenant(
    tenant UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config(
        'app.current_tenant',
        tenant::TEXT,
        false
    );
END;
$$;