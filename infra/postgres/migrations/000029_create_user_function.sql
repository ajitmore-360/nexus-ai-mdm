CREATE OR REPLACE FUNCTION app_context.set_user(
    user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config(
        'app.current_user',
        user_id::TEXT,
        false
    );
END;
$$;

CREATE OR REPLACE FUNCTION app_context.current_user_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
    SELECT current_setting(
        'app.current_user',
        true
    )::UUID
$$;

