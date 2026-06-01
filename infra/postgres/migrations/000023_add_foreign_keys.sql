--
-- ============================================
-- ENTITY FOREIGN KEYS
-- ============================================
--

ALTER TABLE core_mdm.entities
ADD CONSTRAINT fk_entities_tenant
FOREIGN KEY (tenant_id)
REFERENCES core_mdm.tenants(tenant_id);

ALTER TABLE core_mdm.entity_attributes
ADD CONSTRAINT fk_entity_attributes_entity
FOREIGN KEY (entity_id)
REFERENCES core_mdm.entities(entity_id)
ON DELETE CASCADE;

ALTER TABLE core_mdm.golden_records
ADD CONSTRAINT fk_golden_records_tenant
FOREIGN KEY (tenant_id)
REFERENCES core_mdm.tenants(tenant_id);