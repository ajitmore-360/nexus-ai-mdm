
DROP POLICY IF EXISTS tenant_isolation_entities
ON core_mdm.entities;

CREATE POLICY tenant_isolation_entities
ON core_mdm.entities
USING (
    tenant_id = app_context.current_tenant()
);

DROP POLICY IF EXISTS tenant_insert_entities
ON core_mdm.entities;

CREATE POLICY tenant_insert_entities
ON core_mdm.entities
FOR INSERT
WITH CHECK (
    tenant_id = app_context.current_tenant()
);

DROP POLICY IF EXISTS tenant_update_entities
ON core_mdm.entities;

CREATE POLICY tenant_update_entities
ON core_mdm.entities
FOR UPDATE
USING (
    tenant_id = app_context.current_tenant()
);

DROP POLICY IF EXISTS tenant_delete_entities
ON core_mdm.entities;

CREATE POLICY tenant_delete_entities
ON core_mdm.entities
FOR DELETE
USING (
    tenant_id = app_context.current_tenant()
);