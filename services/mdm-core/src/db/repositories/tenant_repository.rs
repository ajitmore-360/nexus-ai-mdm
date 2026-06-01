use chrono::Utc;

use serde::{
    Deserialize,
    Serialize,
};

use serde_json::Value;

use sqlx::{
    PgPool,
    Row,
};

use uuid::Uuid;

//
// ========================================
// TENANT MODEL
// ========================================
//

#[derive(
    Debug,
    Clone,
    Serialize,
    Deserialize,
)]
pub struct Tenant {

    pub tenant_id:
        Uuid,

    pub tenant_code:
        String,

    pub tenant_name:
        String,

    pub status:
        String,

    pub configuration:
        Value,

    pub metadata:
        Value,

    pub created_at:
        chrono::DateTime<Utc>,

    pub updated_at:
        chrono::DateTime<Utc>,
}

//
// ========================================
// TENANT BOOTSTRAP REQUEST
// ========================================
//

#[derive(
    Debug,
    Clone,
    Serialize,
    Deserialize,
)]
pub struct TenantBootstrapRequest {

    pub tenant_code:
        String,

    pub tenant_name:
        String,

    pub admin_email:
        String,

    pub configuration:
        Option<Value>,
}

//
// ========================================
// TENANT REPOSITORY
// ========================================
//

#[derive(Clone)]
pub struct TenantRepository {

    pub pool:
        PgPool,
}

impl TenantRepository {

    //
    // ====================================
    // CONSTRUCTOR
    // ====================================
    //

    pub fn new(
        pool: PgPool,
    ) -> Self {

        Self {
            pool,
        }
    }

    //
    // ====================================
    // CREATE TENANT
    // ====================================
    //

    pub async fn create_tenant(
        &self,
        request: TenantBootstrapRequest,
    ) -> Result<
        Tenant,
        sqlx::Error,
    > {

        let tenant_id =
            Uuid::new_v4();

        let now =
            Utc::now();

        let configuration =
            request
                .configuration
                .unwrap_or_else(|| {
                    serde_json::json!({
                        "ai_enabled": true,
                        "rag_enabled": true,
                        "copilot_enabled": true,
                        "vector_search_enabled": true,
                        "max_users": 100,
                        "storage_quota_gb": 100
                    })
                });

        let metadata =
            serde_json::json!({
                "bootstrap_source": "system",
                "bootstrap_version": "v1",
                "admin_email": request.admin_email
            });

        sqlx::query(
            r#"
            INSERT INTO platform.tenants
            (
                tenant_id,
                tenant_code,
                tenant_name,
                status,
                configuration,
                metadata,
                created_at,
                updated_at
            )
            VALUES
            (
                $1,
                $2,
                $3,
                $4,
                $5,
                $6,
                $7,
                $8
            )
            "#
        )
        .bind(tenant_id)
        .bind(&request.tenant_code)
        .bind(&request.tenant_name)
        .bind("ACTIVE")
        .bind(&configuration)
        .bind(&metadata)
        .bind(now)
        .bind(now)
        .execute(&self.pool)
        .await?;

        Ok(
            Tenant {

                tenant_id,

                tenant_code:
                    request.tenant_code,

                tenant_name:
                    request.tenant_name,

                status:
                    "ACTIVE"
                        .to_string(),

                configuration,

                metadata,

                created_at:
                    now,

                updated_at:
                    now,
            }
        )
    }

    //
    // ====================================
    // GET TENANT BY ID
    // ====================================
    //

    pub async fn get_tenant_by_id(
        &self,
        tenant_id: Uuid,
    ) -> Result<
        Option<Tenant>,
        sqlx::Error,
    > {

        let row =
            sqlx::query(
                r#"
                SELECT
                    tenant_id,
                    tenant_code,
                    tenant_name,
                    status,
                    configuration,
                    metadata,
                    created_at,
                    updated_at
                FROM platform.tenants
                WHERE tenant_id = $1
                "#
            )
            .bind(tenant_id)
            .fetch_optional(&self.pool)
            .await?;

        match row {

            Some(row) => {

                Ok(
                    Some(
                        Tenant {

                            tenant_id:
                                row.get("tenant_id"),

                            tenant_code:
                                row.get("tenant_code"),

                            tenant_name:
                                row.get("tenant_name"),

                            status:
                                row.get("status"),

                            configuration:
                                row.get("configuration"),

                            metadata:
                                row.get("metadata"),

                            created_at:
                                row.get("created_at"),

                            updated_at:
                                row.get("updated_at"),
                        }
                    )
                )
            }

            None => Ok(None),
        }
    }

    //
    // ====================================
    // GET TENANT BY CODE
    // ====================================
    //

    pub async fn get_tenant_by_code(
        &self,
        tenant_code: &str,
    ) -> Result<
        Option<Tenant>,
        sqlx::Error,
    > {

        let row =
            sqlx::query(
                r#"
                SELECT
                    tenant_id,
                    tenant_code,
                    tenant_name,
                    status,
                    configuration,
                    metadata,
                    created_at,
                    updated_at
                FROM platform.tenants
                WHERE tenant_code = $1
                "#
            )
            .bind(tenant_code)
            .fetch_optional(&self.pool)
            .await?;

        match row {

            Some(row) => {

                Ok(
                    Some(
                        Tenant {

                            tenant_id:
                                row.get("tenant_id"),

                            tenant_code:
                                row.get("tenant_code"),

                            tenant_name:
                                row.get("tenant_name"),

                            status:
                                row.get("status"),

                            configuration:
                                row.get("configuration"),

                            metadata:
                                row.get("metadata"),

                            created_at:
                                row.get("created_at"),

                            updated_at:
                                row.get("updated_at"),
                        }
                    )
                )
            }

            None => Ok(None),
        }
    }

    //
    // ====================================
    // LIST TENANTS
    // ====================================
    //

    pub async fn list_tenants(
        &self,
        limit: i64,
        offset: i64,
    ) -> Result<
        Vec<Tenant>,
        sqlx::Error,
    > {

        let rows =
            sqlx::query(
                r#"
                SELECT
                    tenant_id,
                    tenant_code,
                    tenant_name,
                    status,
                    configuration,
                    metadata,
                    created_at,
                    updated_at
                FROM platform.tenants
                ORDER BY created_at DESC
                LIMIT $1
                OFFSET $2
                "#
            )
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.pool)
            .await?;

        let tenants =
            rows
                .into_iter()
                .map(|row| {

                    Tenant {

                        tenant_id:
                            row.get("tenant_id"),

                        tenant_code:
                            row.get("tenant_code"),

                        tenant_name:
                            row.get("tenant_name"),

                        status:
                            row.get("status"),

                        configuration:
                            row.get("configuration"),

                        metadata:
                            row.get("metadata"),

                        created_at:
                            row.get("created_at"),

                        updated_at:
                            row.get("updated_at"),
                    }
                })
                .collect();

        Ok(tenants)
    }

    //
    // ====================================
    // UPDATE TENANT STATUS
    // ====================================
    //

    pub async fn update_tenant_status(
        &self,
        tenant_id: Uuid,
        status: &str,
    ) -> Result<
        u64,
        sqlx::Error,
    > {

        let result =
            sqlx::query(
                r#"
                UPDATE platform.tenants
                SET
                    status = $2,
                    updated_at = NOW()
                WHERE tenant_id = $1
                "#
            )
            .bind(tenant_id)
            .bind(status)
            .execute(&self.pool)
            .await?;

        Ok(
            result.rows_affected()
        )
    }

    //
    // ====================================
    // UPDATE CONFIGURATION
    // ====================================
    //

    pub async fn update_configuration(
        &self,
        tenant_id: Uuid,
        configuration: Value,
    ) -> Result<
        u64,
        sqlx::Error,
    > {

        let result =
            sqlx::query(
                r#"
                UPDATE platform.tenants
                SET
                    configuration = $2,
                    updated_at = NOW()
                WHERE tenant_id = $1
                "#
            )
            .bind(tenant_id)
            .bind(configuration)
            .execute(&self.pool)
            .await?;

        Ok(
            result.rows_affected()
        )
    }

    //
    // ====================================
    // DELETE TENANT
    // ====================================
    //

    pub async fn delete_tenant(
        &self,
        tenant_id: Uuid,
    ) -> Result<
        u64,
        sqlx::Error,
    > {

        let result =
            sqlx::query(
                r#"
                DELETE FROM platform.tenants
                WHERE tenant_id = $1
                "#
            )
            .bind(tenant_id)
            .execute(&self.pool)
            .await?;

        Ok(
            result.rows_affected()
        )
    }

    //
    // ====================================
    // TENANT EXISTS
    // ====================================
    //

    pub async fn tenant_exists(
        &self,
        tenant_id: Uuid,
    ) -> Result<
        bool,
        sqlx::Error,
    > {

        let row =
            sqlx::query(
                r#"
                SELECT EXISTS
                (
                    SELECT 1
                    FROM platform.tenants
                    WHERE tenant_id = $1
                )
                "#
            )
            .bind(tenant_id)
            .fetch_one(&self.pool)
            .await?;

        Ok(
            row.get::<bool, _>(0)
        )
    }

    //
    // ====================================
    // COUNT TENANTS
    // ====================================
    //

    pub async fn count_tenants(
        &self,
    ) -> Result<
        i64,
        sqlx::Error,
    > {

        let row =
            sqlx::query(
                r#"
                SELECT COUNT(*)
                FROM platform.tenants
                "#
            )
            .fetch_one(&self.pool)
            .await?;

        Ok(
            row.get::<i64, _>(0)
        )
    }

    //
    // ====================================
    // BOOTSTRAP DEFAULT ENTITY TYPES
    // ====================================
    //

    pub async fn bootstrap_default_entity_types(
        &self,
        tenant_id: Uuid,
    ) -> Result<
        (),
        sqlx::Error,
    > {

        let entity_types =
            vec![
                (
                    "CUSTOMER",
                    "Customer Master"
                ),
                (
                    "VENDOR",
                    "Vendor Master"
                ),
                (
                    "ACCOUNT",
                    "Account Master"
                ),
                (
                    "BANK",
                    "Bank Master"
                ),
                (
                    "EMPLOYEE",
                    "Employee Master"
                ),
                (
                    "PRODUCT",
                    "Product Master"
                ),
            ];

        for (
            code,
            name,
        ) in entity_types
        {
            sqlx::query(
                r#"
                INSERT INTO core_mdm.entity_types
                (
                    entity_type_id,
                    tenant_id,
                    entity_type_code,
                    entity_type_name,
                    configuration,
                    created_at,
                    updated_at
                )
                VALUES
                (
                    $1,
                    $2,
                    $3,
                    $4,
                    $5,
                    NOW(),
                    NOW()
                )
                ON CONFLICT DO NOTHING
                "#
            )
            .bind(Uuid::new_v4())
            .bind(tenant_id)
            .bind(code)
            .bind(name)
            .bind(
                serde_json::json!({
                    "ai_matching": true,
                    "survivorship_enabled": true,
                    "vector_enabled": true,
                    "copilot_enabled": true
                })
            )
            .execute(&self.pool)
            .await?;
        }

        Ok(())
    }

    //
    // ====================================
    // FULL TENANT BOOTSTRAP
    // ====================================
    //

    pub async fn bootstrap_tenant(
        &self,
        request: TenantBootstrapRequest,
    ) -> Result<
        Tenant,
        sqlx::Error,
    > {

        let tenant =
            self
                .create_tenant(request)
                .await?;

        self
            .bootstrap_default_entity_types(
                tenant.tenant_id
            )
            .await?;

        Ok(tenant)
    }
}