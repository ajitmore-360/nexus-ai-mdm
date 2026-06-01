CREATE OR REPLACE FUNCTION app_context.current_tenant()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
    SELECT current_setting(
        'app.current_tenant',
        true
    )::UUID
$$;