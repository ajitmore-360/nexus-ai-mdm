// ============================================================================
// SCIM 2.0 Service
//
// Maps SCIM Users → core_mdm.identities + core_mdm.tenant_memberships
// Maps SCIM Groups → role collections within a tenant
// ============================================================================

use anyhow::{anyhow, bail, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

// ── SCIM 2.0 canonical types (RFC 7643) ──────────────────────────────────────

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ScimMeta {
    #[serde(rename = "resourceType")]
    pub resource_type: String,
    #[serde(rename = "created", skip_serializing_if = "Option::is_none")]
    pub created: Option<String>,
    #[serde(rename = "lastModified", skip_serializing_if = "Option::is_none")]
    pub last_modified: Option<String>,
    #[serde(rename = "location", skip_serializing_if = "Option::is_none")]
    pub location: Option<String>,
    #[serde(rename = "version", skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ScimEmail {
    pub value: String,
    #[serde(rename = "type", skip_serializing_if = "Option::is_none")]
    pub r#type: Option<String>,
    pub primary: bool,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ScimName {
    #[serde(rename = "formatted", skip_serializing_if = "Option::is_none")]
    pub formatted: Option<String>,
    #[serde(rename = "givenName", skip_serializing_if = "Option::is_none")]
    pub given_name: Option<String>,
    #[serde(rename = "familyName", skip_serializing_if = "Option::is_none")]
    pub family_name: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ScimGroupMember {
    pub value: String,
    #[serde(rename = "display", skip_serializing_if = "Option::is_none")]
    pub display: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ScimUser {
    pub schemas: Vec<String>,
    pub id: String,
    #[serde(rename = "userName")]
    pub user_name: String,
    #[serde(rename = "displayName", skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<ScimName>,
    pub emails: Vec<ScimEmail>,
    pub active: bool,
    pub meta: ScimMeta,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ScimGroup {
    pub schemas: Vec<String>,
    pub id: String,
    #[serde(rename = "displayName")]
    pub display_name: String,
    pub members: Vec<ScimGroupMember>,
    pub meta: ScimMeta,
}

#[derive(Debug, Serialize)]
pub struct ScimListResponse<T: Serialize> {
    pub schemas: Vec<String>,
    #[serde(rename = "totalResults")]
    pub total_results: i64,
    #[serde(rename = "startIndex")]
    pub start_index: i64,
    #[serde(rename = "itemsPerPage")]
    pub items_per_page: i64,
    #[serde(rename = "Resources")]
    pub resources: Vec<T>,
}

#[derive(Debug, Serialize)]
pub struct ScimError {
    pub schemas: Vec<String>,
    pub detail: String,
    pub status: u16,
}

impl ScimError {
    pub fn new(status: u16, detail: &str) -> Self {
        ScimError {
            schemas: vec!["urn:ietf:params:scim:api:messages:2.0:Error".into()],
            detail: detail.to_string(),
            status,
        }
    }
}

// ── Input payloads ────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct CreateScimUser {
    #[serde(rename = "userName")]
    pub user_name: Option<String>,
    #[serde(rename = "displayName")]
    pub display_name: Option<String>,
    pub name: Option<ScimName>,
    pub emails: Option<Vec<ScimEmail>>,
    pub active: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct CreateScimGroup {
    #[serde(rename = "displayName")]
    pub display_name: String,
    pub members: Option<Vec<ScimGroupMember>>,
}

#[derive(Debug, Deserialize)]
pub struct ScimPatch {
    #[serde(rename = "Operations")]
    pub operations: Vec<ScimPatchOp>,
}

#[derive(Debug, Deserialize)]
pub struct ScimPatchOp {
    pub op: String, // "add" | "replace" | "remove"
    pub path: Option<String>,
    pub value: Option<serde_json::Value>,
}

// ── DB identity row (minimal) ─────────────────────────────────────────────────

#[derive(Debug, sqlx::FromRow)]
struct IdentityRow {
    identity_id:  Uuid,
    email:        String,
    display_name: String,                          // NOT NULL DEFAULT ''
    is_active:    bool,                            // added in migration 0024
    created_at:   chrono::DateTime<Utc>,
    updated_at:   Option<chrono::DateTime<Utc>>,   // nullable
}


// ── Service ───────────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct ScimService {
    db: PgPool,
    base_url: String,
}

impl ScimService {
    pub fn new(db: PgPool, base_url: String) -> Self {
        Self { db, base_url }
    }

    fn user_location(&self, tenant_id: Uuid, identity_id: Uuid) -> String {
        format!("{}/scim/{}/v2/Users/{}", self.base_url, tenant_id, identity_id)
    }

    fn group_location(&self, tenant_id: Uuid, role: &str) -> String {
        format!("{}/scim/{}/v2/Groups/{}", self.base_url, tenant_id, role)
    }

    // ── Users ─────────────────────────────────────────────────────────────────

    pub async fn list_users(
        &self,
        tenant_id: Uuid,
        filter: Option<&str>,
        start_index: i64,
        count: i64,
    ) -> Result<ScimListResponse<ScimUser>> {
        // Basic filter: "userName eq 'x'" or "email eq 'x'"
        let (email_filter, name_filter): (Option<String>, Option<String>) =
            parse_scim_filter(filter);

        let rows = sqlx::query_as::<_, IdentityRow>(
            r#"
            SELECT i.identity_id, i.email, i.display_name, i.is_active, i.created_at, i.updated_at
            FROM core_mdm.identities i
            JOIN core_mdm.tenant_memberships tm ON tm.identity_id = i.identity_id
            WHERE tm.tenant_id = $1
              AND ($2::text IS NULL OR i.email ILIKE $2)
              AND ($3::text IS NULL OR i.display_name ILIKE $3)
            ORDER BY i.created_at
            LIMIT $4 OFFSET $5
            "#,
        )
        .bind(tenant_id)
        .bind(email_filter.as_deref())
        .bind(name_filter.as_deref())
        .bind(count)
        .bind(start_index - 1)
        .fetch_all(&self.db)
        .await?;

        let total: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM core_mdm.identities i
            JOIN core_mdm.tenant_memberships tm ON tm.identity_id = i.identity_id
            WHERE tm.tenant_id = $1
            "#,
        )
        .bind(tenant_id)
        .fetch_one(&self.db)
        .await?;

        let users = self.rows_to_users(tenant_id, rows).await?;
        Ok(ScimListResponse {
            schemas: vec!["urn:ietf:params:scim:api:messages:2.0:ListResponse".into()],
            total_results: total,
            start_index,
            items_per_page: count,
            resources: users,
        })
    }

    pub async fn get_user(&self, tenant_id: Uuid, identity_id: Uuid) -> Result<ScimUser> {
        let row = sqlx::query_as::<_, IdentityRow>(
            r#"
            SELECT i.identity_id, i.email, i.display_name, i.is_active, i.created_at, i.updated_at
            FROM core_mdm.identities i
            JOIN core_mdm.tenant_memberships tm ON tm.identity_id = i.identity_id
            WHERE tm.tenant_id = $1 AND i.identity_id = $2
            "#,
        )
        .bind(tenant_id)
        .bind(identity_id)
        .fetch_optional(&self.db)
        .await?
        .ok_or_else(|| anyhow!("User not found"))?;

        self.row_to_user(tenant_id, row).await
    }

    pub async fn create_user(
        &self,
        tenant_id: Uuid,
        payload: CreateScimUser,
        default_role: &str,
    ) -> Result<ScimUser> {
        let email = extract_primary_email(&payload.emails, &payload.user_name)
            .ok_or_else(|| anyhow!("No valid email provided"))?;

        let display_name = payload.display_name
            .or_else(|| payload.name.as_ref().and_then(|n| n.formatted.clone()))
            .or_else(|| {
                payload.name.as_ref().map(|n| {
                    format!(
                        "{} {}",
                        n.given_name.as_deref().unwrap_or(""),
                        n.family_name.as_deref().unwrap_or("")
                    )
                    .trim()
                    .to_string()
                })
            });
        let active = payload.active.unwrap_or(true);

        let mut tx = self.db.begin().await?;

        // Upsert identity (email is globally unique)
        let identity: IdentityRow = sqlx::query_as(
            r#"
            INSERT INTO core_mdm.identities (email, display_name, is_active, auth_provider)
            VALUES ($1, COALESCE($2, ''), $3, 'scim')
            ON CONFLICT (email) DO UPDATE SET
                display_name = COALESCE(NULLIF($2, ''), identities.display_name),
                is_active    = $3,
                updated_at   = NOW()
            RETURNING identity_id, email, display_name, is_active, created_at, updated_at
            "#,
        )
        .bind(&email)
        .bind(display_name.as_deref().unwrap_or(""))
        .bind(active)
        .fetch_one(&mut *tx)
        .await?;

        // Upsert tenant membership
        sqlx::query(
            r#"
            INSERT INTO core_mdm.tenant_memberships (tenant_id, identity_id, role)
            VALUES ($1, $2, $3)
            ON CONFLICT (tenant_id, identity_id) DO UPDATE SET
                role = $3
            "#,
        )
        .bind(tenant_id)
        .bind(identity.identity_id)
        .bind(default_role)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        self.row_to_user(tenant_id, identity).await
    }

    pub async fn update_user(
        &self,
        tenant_id: Uuid,
        identity_id: Uuid,
        payload: CreateScimUser,
        _default_role: &str,
    ) -> Result<ScimUser> {
        // Verify membership
        let exists: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM core_mdm.tenant_memberships WHERE tenant_id=$1 AND identity_id=$2)",
        )
        .bind(tenant_id)
        .bind(identity_id)
        .fetch_one(&self.db)
        .await?;
        if !exists { bail!("User not found in tenant") }

        let display_name = payload.display_name
            .or_else(|| payload.name.as_ref().and_then(|n| n.formatted.clone()));
        let active = payload.active.unwrap_or(true);

        let row: IdentityRow = sqlx::query_as(
            r#"
            UPDATE core_mdm.identities
            SET display_name = COALESCE(NULLIF($2, ''), display_name),
                is_active    = $3,
                updated_at   = NOW()
            WHERE identity_id = $1
            RETURNING identity_id, email, display_name, is_active, created_at, updated_at
            "#,
        )
        .bind(identity_id)
        .bind(display_name.as_deref().unwrap_or(""))
        .bind(active)
        .fetch_one(&self.db)
        .await?;

        self.row_to_user(tenant_id, row).await
    }

    pub async fn patch_user(
        &self,
        tenant_id: Uuid,
        identity_id: Uuid,
        patch: ScimPatch,
    ) -> Result<ScimUser> {
        let mut active_override: Option<bool> = None;
        let mut display_name_override: Option<String> = None;

        for op in &patch.operations {
            match op.op.to_lowercase().as_str() {
                "replace" | "add" => {
                    let path = op.path.as_deref().unwrap_or("");
                    if let Some(ref val) = op.value {
                        match path {
                            "active" => {
                                active_override = val.as_bool();
                            }
                            "displayName" => {
                                display_name_override = val.as_str().map(|s| s.to_string());
                            }
                            "" => {
                                // value is an object
                                if let Some(obj) = val.as_object() {
                                    if let Some(b) = obj.get("active").and_then(|v| v.as_bool()) {
                                        active_override = Some(b);
                                    }
                                    if let Some(s) = obj.get("displayName").and_then(|v| v.as_str()) {
                                        display_name_override = Some(s.to_string());
                                    }
                                }
                            }
                            _ => {}
                        }
                    }
                }
                _ => {}
            }
        }

        sqlx::query(
            r#"
            UPDATE core_mdm.identities SET
                is_active    = COALESCE($2, is_active),
                display_name = COALESCE($3, display_name),
                updated_at   = NOW()
            WHERE identity_id = $1
            "#,
        )
        .bind(identity_id)
        .bind(active_override)
        .bind(display_name_override.as_deref())
        .execute(&self.db)
        .await?;

        self.get_user(tenant_id, identity_id).await
    }

    pub async fn delete_user(&self, tenant_id: Uuid, identity_id: Uuid) -> Result<()> {
        // Soft-delete: deactivate + remove from tenant
        let mut tx = self.db.begin().await?;
        sqlx::query(
            "UPDATE core_mdm.identities SET is_active=false, updated_at=NOW() WHERE identity_id=$1",
        )
        .bind(identity_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "DELETE FROM core_mdm.tenant_memberships WHERE tenant_id=$1 AND identity_id=$2",
        )
        .bind(tenant_id)
        .bind(identity_id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(())
    }

    // ── Groups (mapped to roles) ──────────────────────────────────────────────
    //
    // SCIM Groups in Nexus map to tenant roles (admin, steward, viewer, etc.).
    // Group ID is the role code; displayName is the human-readable role name.

    pub async fn list_groups(
        &self,
        tenant_id: Uuid,
        start_index: i64,
        count: i64,
    ) -> Result<ScimListResponse<ScimGroup>> {
        #[derive(sqlx::FromRow)]
        struct RoleRow {
            role: String,
        }

        let rows = sqlx::query_as::<_, RoleRow>(
            r#"
            SELECT DISTINCT role
            FROM core_mdm.tenant_memberships
            WHERE tenant_id = $1
            ORDER BY role
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(tenant_id)
        .bind(count)
        .bind(start_index - 1)
        .fetch_all(&self.db)
        .await?;

        let total = rows.len() as i64;
        let mut groups = Vec::new();
        for row in rows {
            let members = self.get_role_members(tenant_id, &row.role).await?;
            groups.push(ScimGroup {
                schemas: vec!["urn:ietf:params:scim:schemas:core:2.0:Group".into()],
                id: row.role.clone(),
                display_name: role_display_name(&row.role),
                members,
                meta: ScimMeta {
                    resource_type: "Group".into(),
                    created: None,
                    last_modified: None,
                    location: Some(self.group_location(tenant_id, &row.role)),
                    version: None,
                },
            });
        }

        Ok(ScimListResponse {
            schemas: vec!["urn:ietf:params:scim:api:messages:2.0:ListResponse".into()],
            total_results: total,
            start_index,
            items_per_page: count,
            resources: groups,
        })
    }

    pub async fn get_group(&self, tenant_id: Uuid, role: &str) -> Result<ScimGroup> {
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM core_mdm.tenant_memberships WHERE tenant_id=$1 AND role=$2",
        )
        .bind(tenant_id)
        .bind(role)
        .fetch_one(&self.db)
        .await?;
        if count == 0 {
            bail!("Group not found");
        }
        let members = self.get_role_members(tenant_id, role).await?;
        Ok(ScimGroup {
            schemas: vec!["urn:ietf:params:scim:schemas:core:2.0:Group".into()],
            id: role.to_string(),
            display_name: role_display_name(role),
            members,
            meta: ScimMeta {
                resource_type: "Group".into(),
                created: None,
                last_modified: None,
                location: Some(self.group_location(tenant_id, role)),
                version: None,
            },
        })
    }

    /// Patch group members: add or remove members by identity_id.
    pub async fn patch_group(
        &self,
        tenant_id: Uuid,
        role: &str,
        patch: ScimPatch,
    ) -> Result<ScimGroup> {
        for op in &patch.operations {
            match op.op.to_lowercase().as_str() {
                "add" => {
                    if let Some(members) = op.value.as_ref().and_then(|v| v.as_array()) {
                        for member in members {
                            if let Some(id_str) = member.get("value").and_then(|v| v.as_str()) {
                                if let Ok(identity_id) = Uuid::parse_str(id_str) {
                                    sqlx::query(
                                        r#"
                                        INSERT INTO core_mdm.tenant_memberships (tenant_id, identity_id, role)
                                        VALUES ($1, $2, $3)
                                        ON CONFLICT (tenant_id, identity_id) DO UPDATE SET role=$3
                                        "#,
                                    )
                                    .bind(tenant_id)
                                    .bind(identity_id)
                                    .bind(role)
                                    .execute(&self.db)
                                    .await?;
                                }
                            }
                        }
                    }
                }
                "remove" => {
                    if let Some(members) = op.value.as_ref().and_then(|v| v.as_array()) {
                        for member in members {
                            if let Some(id_str) = member.get("value").and_then(|v| v.as_str()) {
                                if let Ok(identity_id) = Uuid::parse_str(id_str) {
                                    sqlx::query(
                                        "DELETE FROM core_mdm.tenant_memberships WHERE tenant_id=$1 AND identity_id=$2 AND role=$3",
                                    )
                                    .bind(tenant_id)
                                    .bind(identity_id)
                                    .bind(role)
                                    .execute(&self.db)
                                    .await?;
                                }
                            }
                        }
                    }
                }
                _ => {}
            }
        }
        self.get_group(tenant_id, role).await
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    async fn rows_to_users(&self, tenant_id: Uuid, rows: Vec<IdentityRow>) -> Result<Vec<ScimUser>> {
        let mut out = Vec::with_capacity(rows.len());
        for row in rows {
            out.push(self.row_to_user(tenant_id, row).await?);
        }
        Ok(out)
    }

    async fn row_to_user(&self, tenant_id: Uuid, row: IdentityRow) -> Result<ScimUser> {
        let name_str = if row.display_name.is_empty() { None } else { Some(row.display_name.clone()) };
        let name_parts: Vec<&str> = row.display_name.splitn(2, ' ').collect();
        let given  = name_parts.first().filter(|s| !s.is_empty()).map(|s| s.to_string());
        let family = name_parts.get(1).filter(|s| !s.is_empty()).map(|s| s.to_string());

        Ok(ScimUser {
            schemas: vec!["urn:ietf:params:scim:schemas:core:2.0:User".into()],
            id: row.identity_id.to_string(),
            user_name: row.email.clone(),
            display_name: name_str.clone(),
            name: Some(ScimName {
                formatted: name_str,
                given_name: given,
                family_name: family,
            }),
            emails: vec![ScimEmail {
                value: row.email.clone(),
                r#type: Some("work".into()),
                primary: true,
            }],
            active: row.is_active,
            meta: ScimMeta {
                resource_type: "User".into(),
                created: Some(row.created_at.to_rfc3339()),
                last_modified: row.updated_at.map(|t| t.to_rfc3339()),
                location: Some(self.user_location(tenant_id, row.identity_id)),
                version: None,
            },
        })
    }

    async fn get_role_members(&self, tenant_id: Uuid, role: &str) -> Result<Vec<ScimGroupMember>> {
        #[derive(sqlx::FromRow)]
        struct M { identity_id: Uuid, email: String }
        let rows = sqlx::query_as::<_, M>(
            r#"
            SELECT i.identity_id, i.email
            FROM core_mdm.tenant_memberships tm
            JOIN core_mdm.identities i ON i.identity_id = tm.identity_id
            WHERE tm.tenant_id=$1 AND tm.role=$2
            "#,
        )
        .bind(tenant_id)
        .bind(role)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.into_iter().map(|r| ScimGroupMember {
            value: r.identity_id.to_string(),
            display: Some(r.email),
        }).collect())
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn extract_primary_email(
    emails: &Option<Vec<ScimEmail>>,
    user_name: &Option<String>,
) -> Option<String> {
    if let Some(ref list) = emails {
        if let Some(primary) = list.iter().find(|e| e.primary) {
            if primary.value.contains('@') {
                return Some(primary.value.clone());
            }
        }
        if let Some(first) = list.first() {
            if first.value.contains('@') {
                return Some(first.value.clone());
            }
        }
    }
    user_name.as_ref().filter(|s| s.contains('@')).cloned()
}

fn parse_scim_filter(filter: Option<&str>) -> (Option<String>, Option<String>) {
    let Some(f) = filter else { return (None, None) };
    // Support: userName eq "x" | email eq "x" | displayName co "x"
    let lower = f.to_lowercase();
    let email_filter = if lower.contains("username eq") || lower.contains("email eq") {
        extract_filter_value(f).map(|v| format!("%{}%", v))
    } else {
        None
    };
    let name_filter = if lower.contains("displayname") {
        extract_filter_value(f).map(|v| format!("%{}%", v))
    } else {
        None
    };
    (email_filter, name_filter)
}

fn extract_filter_value(filter: &str) -> Option<String> {
    // "userName eq \"alice@example.com\"" → "alice@example.com"
    let start = filter.find('"')? + 1;
    let end = filter.rfind('"')?;
    if end > start { Some(filter[start..end].to_string()) } else { None }
}

fn role_display_name(role: &str) -> String {
    match role {
        "admin"          => "Administrators",
        "business_admin" => "Business Administrators",
        "steward"        => "Data Stewards",
        "viewer"         => "Viewers",
        "analyst"        => "Analysts",
        other            => other,
    }
    .to_string()
}
