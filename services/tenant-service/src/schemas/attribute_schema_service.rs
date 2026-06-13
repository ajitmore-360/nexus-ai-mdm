use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// A single attribute definition for an entity type.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttributeSchema {
    pub schema_id:     Uuid,
    pub tenant_id:     Option<Uuid>,
    pub entity_type:   String,
    pub attribute_key: String,
    pub display_name:  String,
    pub group_name:    String,
    pub data_type:     String,
    pub is_required:   bool,
    pub is_searchable: bool,
    pub is_filterable: bool,
    pub is_pii:        bool,
    pub is_system:     bool,
    pub enum_values:   Option<Vec<String>>,
    pub default_value: Option<String>,
    pub validation:    Option<Value>,
    pub display_order: i32,
    pub placeholder:   Option<String>,
    pub help_text:     Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct CreateAttributeRequest {
    pub attribute_key: String,
    pub display_name:  String,
    pub group_name:    Option<String>,
    pub data_type:     String,
    pub is_required:   Option<bool>,
    pub is_pii:        Option<bool>,
    pub enum_values:   Option<Vec<String>>,
    pub validation:    Option<Value>,
    pub display_order: Option<i32>,
    pub placeholder:   Option<String>,
    pub help_text:     Option<String>,
}

/// Returns the merged attribute schema for a given entity type.
///
/// Merges: global defaults (tenant_id IS NULL) UNION tenant-specific overrides.
/// Tenant-specific attributes take precedence when attribute_key matches.
pub async fn get_schema(
    pool:        &PgPool,
    tenant_id:   Uuid,
    entity_type: &str,
) -> Result<Vec<AttributeSchema>> {
    let rows = sqlx::query(
        r#"
        -- Tenant-specific overrides first, global defaults as fallback
        SELECT DISTINCT ON (attribute_key)
            schema_id, tenant_id, entity_type, attribute_key, display_name,
            group_name, data_type, is_required, is_searchable, is_filterable,
            is_pii, is_system, enum_values, default_value, validation,
            display_order, placeholder, help_text
        FROM core_mdm.attribute_schemas
        WHERE entity_type = $1
          AND (tenant_id = $2 OR tenant_id IS NULL)
        ORDER BY attribute_key, tenant_id NULLS LAST, display_order
        "#,
    )
    .bind(entity_type)
    .bind(tenant_id)
    .fetch_all(pool)
    .await?;

    let schemas: Vec<AttributeSchema> = rows
        .into_iter()
        .map(|r| AttributeSchema {
            schema_id:     r.try_get("schema_id").unwrap_or(Uuid::nil()),
            tenant_id:     r.try_get("tenant_id").ok().flatten(),
            entity_type:   r.try_get("entity_type").unwrap_or_default(),
            attribute_key: r.try_get("attribute_key").unwrap_or_default(),
            display_name:  r.try_get("display_name").unwrap_or_default(),
            group_name:    r.try_get("group_name").unwrap_or_else(|_| "General".to_string()),
            data_type:     r.try_get("data_type").unwrap_or_else(|_| "string".to_string()),
            is_required:   r.try_get("is_required").unwrap_or(false),
            is_searchable: r.try_get("is_searchable").unwrap_or(true),
            is_filterable: r.try_get("is_filterable").unwrap_or(true),
            is_pii:        r.try_get("is_pii").unwrap_or(false),
            is_system:     r.try_get("is_system").unwrap_or(false),
            enum_values:   r.try_get::<Option<sqlx::types::Json<Vec<String>>>, _>("enum_values")
                            .ok().flatten().map(|j| j.0),
            default_value: r.try_get("default_value").ok().flatten(),
            validation:    r.try_get::<Option<sqlx::types::Json<Value>>, _>("validation")
                            .ok().flatten().map(|j| j.0),
            display_order: r.try_get("display_order").unwrap_or(100),
            placeholder:   r.try_get("placeholder").ok().flatten(),
            help_text:     r.try_get("help_text").ok().flatten(),
        })
        .collect();

    // Sort by group then display_order
    let mut result = schemas;
    result.sort_by(|a, b| {
        a.group_name.cmp(&b.group_name)
            .then(a.display_order.cmp(&b.display_order))
    });

    Ok(result)
}

/// List all entity types available in the system.
pub fn available_entity_types() -> Vec<EntityTypeSummary> {
    vec![
        EntityTypeSummary { entity_type: "Customer".into(),     icon: "people_rounded".into(),         prefix: "CUST".into(), description: "Customers buying your products or services".into() },
        EntityTypeSummary { entity_type: "Vendor".into(),       icon: "local_shipping_rounded".into(),  prefix: "VEND".into(), description: "Suppliers and vendors providing goods or services".into() },
        EntityTypeSummary { entity_type: "Product".into(),      icon: "inventory_2_rounded".into(),     prefix: "PROD".into(), description: "Finished goods and products sold to customers".into() },
        EntityTypeSummary { entity_type: "Material".into(),     icon: "science_rounded".into(),         prefix: "MATL".into(), description: "Raw materials and components used in production".into() },
        EntityTypeSummary { entity_type: "Account".into(),      icon: "account_balance_rounded".into(), prefix: "ACCT".into(), description: "Financial accounts and GL accounts".into() },
        EntityTypeSummary { entity_type: "Employee".into(),     icon: "badge_rounded".into(),           prefix: "EMP".into(),  description: "Employees and human resources".into() },
        EntityTypeSummary { entity_type: "Location".into(),     icon: "location_on_rounded".into(),     prefix: "LOC".into(),  description: "Physical locations, offices, and warehouses".into() },
        EntityTypeSummary { entity_type: "Organization".into(), icon: "corporate_fare_rounded".into(),  prefix: "ORG".into(),  description: "Internal legal entities and subsidiaries".into() },
        EntityTypeSummary { entity_type: "Asset".into(),        icon: "devices_rounded".into(),         prefix: "ASST".into(), description: "Physical and digital assets".into() },
    ]
}

#[derive(Debug, Clone, Serialize)]
pub struct EntityTypeSummary {
    pub entity_type: String,
    pub icon:        String,
    pub prefix:      String,
    pub description: String,
}

/// Add a custom attribute for a tenant (schema extension).
pub async fn add_custom_attribute(
    pool:        &PgPool,
    tenant_id:   Uuid,
    entity_type: &str,
    req:         CreateAttributeRequest,
) -> Result<Uuid> {
    let schema_id = Uuid::new_v4();
    sqlx::query(
        r#"
        INSERT INTO core_mdm.attribute_schemas (
            schema_id, tenant_id, entity_type, attribute_key, display_name,
            group_name, data_type, is_required, is_pii, enum_values,
            validation, display_order, placeholder, help_text
        ) VALUES (
            $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14
        )
        "#,
    )
    .bind(schema_id)
    .bind(tenant_id)
    .bind(entity_type)
    .bind(&req.attribute_key)
    .bind(&req.display_name)
    .bind(req.group_name.as_deref().unwrap_or("Custom"))
    .bind(&req.data_type)
    .bind(req.is_required.unwrap_or(false))
    .bind(req.is_pii.unwrap_or(false))
    .bind(req.enum_values.map(|v| serde_json::to_value(v).unwrap()))
    .bind(req.validation)
    .bind(req.display_order.unwrap_or(500))
    .bind(req.placeholder.as_deref())
    .bind(req.help_text.as_deref())
    .execute(pool)
    .await?;

    Ok(schema_id)
}
