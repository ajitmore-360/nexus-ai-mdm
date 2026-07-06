-- Add updated_at to core_mdm.users.
-- Several handlers (invite, accept-invite, change-password, reset-password)
-- write this column; it was missing from the original DDL.

ALTER TABLE core_mdm.users
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;
