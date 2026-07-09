// ============================================================================
// SCIM 2.0 Handlers (RFC 7643 / RFC 7644)
//
// All SCIM endpoints are authenticated via SCIM bearer tokens
// (not the standard JWT auth middleware). The SCIM bearer token
// identifies the tenant; no X-Tenant-ID header required.
//
// Routes prefix: /scim/:tenant_id/v2/
//   GET  /ServiceProviderConfig
//   GET  /Schemas
//   GET  /ResourceTypes
//   GET/POST   /Users
//   GET/PUT/PATCH/DELETE /Users/:id
//   GET/POST   /Groups
//   GET/PUT/PATCH/DELETE /Groups/:id
// ============================================================================

use axum::{
    extract::{Path, Query, State},
    http::{header, HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};
use serde::Deserialize;
use std::sync::Arc;
use uuid::Uuid;

use crate::{
    services::scim_service::{CreateScimGroup, CreateScimUser, ScimError, ScimPatch},
    AppState,
};

// â”€â”€ SCIM bearer token auth helper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

async fn extract_tenant_from_token(
    state: &Arc<AppState>,
    headers: &HeaderMap,
) -> Result<Uuid, (StatusCode, Json<ScimError>)> {
    let auth = headers
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .ok_or_else(|| {
            (
                StatusCode::UNAUTHORIZED,
                Json(ScimError::new(401, "Authorization header required")),
            )
        })?;

    let token = auth
        .strip_prefix("Bearer ")
        .ok_or_else(|| {
            (
                StatusCode::UNAUTHORIZED,
                Json(ScimError::new(401, "Bearer token required")),
            )
        })?;

    state
        .sso_service
        .verify_scim_token(token)
        .await
        .map_err(|e| {
            (
                StatusCode::UNAUTHORIZED,
                Json(ScimError::new(401, &e.to_string())),
            )
        })
}

// â”€â”€ Service Provider Configuration â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

pub async fn scim_service_provider_config(
    Path(_tenant_id_str): Path<String>,
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let _tenant_id = match extract_tenant_from_token(&state, &headers).await {
        Ok(t) => t,
        Err(e) => return e.into_response(),
    };

    let config = serde_json::json!({
        "schemas": ["urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig"],
        "documentationUri": "https://azile-mdm.dev/docs/scim",
        "patch": { "supported": true },
        "bulk": { "supported": false, "maxOperations": 0, "maxPayloadSize": 0 },
        "filter": { "supported": true, "maxResults": 200 },
        "changePassword": { "supported": false },
        "sort": { "supported": false },
        "etag": { "supported": false },
        "authenticationSchemes": [
            {
                "type": "oauthbearertoken",
                "name": "OAuth Bearer Token",
                "description": "Authentication using a pre-issued SCIM bearer token"
            }
        ]
    });
    (StatusCode::OK, Json(config)).into_response()
}

// â”€â”€ Schemas â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

pub async fn scim_schemas(
    Path(_tenant_id_str): Path<String>,
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let _tenant_id = match extract_tenant_from_token(&state, &headers).await {
        Ok(t) => t,
        Err(e) => return e.into_response(),
    };

    let schemas = serde_json::json!({
        "schemas": ["urn:ietf:params:scim:api:messages:2.0:ListResponse"],
        "totalResults": 2,
        "startIndex": 1,
        "itemsPerPage": 2,
        "Resources": [
            {
                "schemas": ["urn:ietf:params:scim:schemas:core:2.0:Schema"],
                "id": "urn:ietf:params:scim:schemas:core:2.0:User",
                "name": "User",
                "description": "User Account",
                "attributes": [
                    { "name": "userName", "type": "string", "required": true, "uniqueness": "server" },
                    { "name": "displayName", "type": "string", "required": false, "uniqueness": "none" },
                    { "name": "emails", "type": "complex", "required": false, "multiValued": true,
                      "subAttributes": [
                        { "name": "value", "type": "string" },
                        { "name": "type", "type": "string" },
                        { "name": "primary", "type": "boolean" }
                      ]
                    },
                    { "name": "active", "type": "boolean", "required": false }
                ]
            },
            {
                "schemas": ["urn:ietf:params:scim:schemas:core:2.0:Schema"],
                "id": "urn:ietf:params:scim:schemas:core:2.0:Group",
                "name": "Group",
                "description": "Group (maps to Nexus MDM roles)",
                "attributes": [
                    { "name": "displayName", "type": "string", "required": true },
                    { "name": "members", "type": "complex", "required": false, "multiValued": true,
                      "subAttributes": [
                        { "name": "value", "type": "string" },
                        { "name": "display", "type": "string" }
                      ]
                    }
                ]
            }
        ]
    });
    (StatusCode::OK, Json(schemas)).into_response()
}

// â”€â”€ Resource Types â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

pub async fn scim_resource_types(
    Path(_tenant_id_str): Path<String>,
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let _tenant_id = match extract_tenant_from_token(&state, &headers).await {
        Ok(t) => t,
        Err(e) => return e.into_response(),
    };

    let rt = serde_json::json!({
        "schemas": ["urn:ietf:params:scim:api:messages:2.0:ListResponse"],
        "totalResults": 2,
        "startIndex": 1,
        "itemsPerPage": 2,
        "Resources": [
            {
                "schemas": ["urn:ietf:params:scim:schemas:core:2.0:ResourceType"],
                "id": "User",
                "name": "User",
                "endpoint": "/Users",
                "schema": "urn:ietf:params:scim:schemas:core:2.0:User"
            },
            {
                "schemas": ["urn:ietf:params:scim:schemas:core:2.0:ResourceType"],
                "id": "Group",
                "name": "Group",
                "endpoint": "/Groups",
                "schema": "urn:ietf:params:scim:schemas:core:2.0:Group"
            }
        ]
    });
    (StatusCode::OK, Json(rt)).into_response()
}

// â”€â”€ Users â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

#[derive(Deserialize)]
pub struct ScimListQuery {
    pub filter: Option<String>,
    #[serde(rename = "startIndex")]
    pub start_index: Option<i64>,
    pub count: Option<i64>,
}

pub async fn scim_list_users(
    Path(_tenant_id_str): Path<String>,
    headers: HeaderMap,
    Query(q): Query<ScimListQuery>,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let tenant_id = match extract_tenant_from_token(&state, &headers).await {
        Ok(t) => t,
        Err(e) => return e.into_response(),
    };

    let start = q.start_index.unwrap_or(1).max(1);
    let count = q.count.unwrap_or(100).clamp(1, 500);

    match state.scim_service.list_users(tenant_id, q.filter.as_deref(), start, count).await {
        Ok(list) => (StatusCode::OK, Json(list)).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ScimError::new(500, &e.to_string()))).into_response(),
    }
}

pub async fn scim_get_user(
    Path((_tenant_id_str, user_id_str)): Path<(String, String)>,
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let tenant_id = match extract_tenant_from_token(&state, &headers).await {
        Ok(t) => t,
        Err(e) => return e.into_response(),
    };
    let user_id = match Uuid::parse_str(&user_id_str) {
        Ok(id) => id,
        Err(_) => return (StatusCode::BAD_REQUEST, Json(ScimError::new(400, "Invalid user ID"))).into_response(),
    };

    match state.scim_service.get_user(tenant_id, user_id).await {
        Ok(user) => (StatusCode::OK, Json(user)).into_response(),
        Err(e) if e.to_string().contains("not found") => {
            (StatusCode::NOT_FOUND, Json(ScimError::new(404, "User not found"))).into_response()
        }
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ScimError::new(500, &e.to_string()))).into_response(),
    }
}

pub async fn scim_create_user(
    Path(_tenant_id_str): Path<String>,
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
    Json(payload): Json<CreateScimUser>,
) -> impl IntoResponse {
    let tenant_id = match extract_tenant_from_token(&state, &headers).await {
        Ok(t) => t,
        Err(e) => return e.into_response(),
    };

    let default_role = get_default_role(&state, tenant_id).await;

    match state.scim_service.create_user(tenant_id, payload, &default_role).await {
        Ok(user) => (StatusCode::CREATED, Json(user)).into_response(),
        Err(e) => (StatusCode::BAD_REQUEST, Json(ScimError::new(400, &e.to_string()))).into_response(),
    }
}

pub async fn scim_update_user(
    Path((_tenant_id_str, user_id_str)): Path<(String, String)>,
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
    Json(payload): Json<CreateScimUser>,
) -> impl IntoResponse {
    let tenant_id = match extract_tenant_from_token(&state, &headers).await {
        Ok(t) => t,
        Err(e) => return e.into_response(),
    };
    let user_id = match Uuid::parse_str(&user_id_str) {
        Ok(id) => id,
        Err(_) => return (StatusCode::BAD_REQUEST, Json(ScimError::new(400, "Invalid user ID"))).into_response(),
    };

    let default_role = get_default_role(&state, tenant_id).await;

    match state.scim_service.update_user(tenant_id, user_id, payload, &default_role).await {
        Ok(user) => (StatusCode::OK, Json(user)).into_response(),
        Err(e) if e.to_string().contains("not found") => {
            (StatusCode::NOT_FOUND, Json(ScimError::new(404, "User not found"))).into_response()
        }
        Err(e) => (StatusCode::BAD_REQUEST, Json(ScimError::new(400, &e.to_string()))).into_response(),
    }
}

pub async fn scim_patch_user(
    Path((_tenant_id_str, user_id_str)): Path<(String, String)>,
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
    Json(patch): Json<ScimPatch>,
) -> impl IntoResponse {
    let tenant_id = match extract_tenant_from_token(&state, &headers).await {
        Ok(t) => t,
        Err(e) => return e.into_response(),
    };
    let user_id = match Uuid::parse_str(&user_id_str) {
        Ok(id) => id,
        Err(_) => return (StatusCode::BAD_REQUEST, Json(ScimError::new(400, "Invalid user ID"))).into_response(),
    };

    match state.scim_service.patch_user(tenant_id, user_id, patch).await {
        Ok(user) => (StatusCode::OK, Json(user)).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ScimError::new(500, &e.to_string()))).into_response(),
    }
}

pub async fn scim_delete_user(
    Path((_tenant_id_str, user_id_str)): Path<(String, String)>,
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let tenant_id = match extract_tenant_from_token(&state, &headers).await {
        Ok(t) => t,
        Err(e) => return e.into_response(),
    };
    let user_id = match Uuid::parse_str(&user_id_str) {
        Ok(id) => id,
        Err(_) => return (StatusCode::BAD_REQUEST, Json(ScimError::new(400, "Invalid user ID"))).into_response(),
    };

    match state.scim_service.delete_user(tenant_id, user_id).await {
        Ok(()) => StatusCode::NO_CONTENT.into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ScimError::new(500, &e.to_string()))).into_response(),
    }
}

// â”€â”€ Groups â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

pub async fn scim_list_groups(
    Path(_tenant_id_str): Path<String>,
    headers: HeaderMap,
    Query(q): Query<ScimListQuery>,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let tenant_id = match extract_tenant_from_token(&state, &headers).await {
        Ok(t) => t,
        Err(e) => return e.into_response(),
    };
    let start = q.start_index.unwrap_or(1).max(1);
    let count = q.count.unwrap_or(100).clamp(1, 200);

    match state.scim_service.list_groups(tenant_id, start, count).await {
        Ok(list) => (StatusCode::OK, Json(list)).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ScimError::new(500, &e.to_string()))).into_response(),
    }
}

pub async fn scim_get_group(
    Path((_tenant_id_str, group_id)): Path<(String, String)>,
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let tenant_id = match extract_tenant_from_token(&state, &headers).await {
        Ok(t) => t,
        Err(e) => return e.into_response(),
    };
    match state.scim_service.get_group(tenant_id, &group_id).await {
        Ok(group) => (StatusCode::OK, Json(group)).into_response(),
        Err(e) if e.to_string().contains("not found") => {
            (StatusCode::NOT_FOUND, Json(ScimError::new(404, "Group not found"))).into_response()
        }
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ScimError::new(500, &e.to_string()))).into_response(),
    }
}

pub async fn scim_create_group(
    Path(_tenant_id_str): Path<String>,
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
    Json(payload): Json<CreateScimGroup>,
) -> impl IntoResponse {
    let tenant_id = match extract_tenant_from_token(&state, &headers).await {
        Ok(t) => t,
        Err(e) => return e.into_response(),
    };

    // Map displayName â†’ role code
    let role_code = display_name_to_role(&payload.display_name);

    // Add all members to this role
    if let Some(ref members) = payload.members {
        for member in members {
            if let Ok(identity_id) = Uuid::parse_str(&member.value) {
                let _ = sqlx::query(
                    r#"
                    INSERT INTO core_mdm.tenant_memberships (tenant_id, identity_id, role)
                    VALUES ($1, $2, $3)
                    ON CONFLICT (tenant_id, identity_id) DO UPDATE SET role=$3
                    "#,
                )
                .bind(tenant_id)
                .bind(identity_id)
                .bind(&role_code)
                .execute(&state.db)
                .await;
            }
        }
    }

    match state.scim_service.get_group(tenant_id, &role_code).await {
        Ok(group) => (StatusCode::CREATED, Json(group)).into_response(),
        Err(_) => {
            // Group might be empty; return a minimal response
            let group = crate::services::scim_service::ScimGroup {
                schemas: vec!["urn:ietf:params:scim:schemas:core:2.0:Group".into()],
                id: role_code.clone(),
                display_name: payload.display_name.clone(),
                members: vec![],
                meta: crate::services::scim_service::ScimMeta {
                    resource_type: "Group".into(),
                    created: None,
                    last_modified: None,
                    location: None,
                    version: None,
                },
            };
            (StatusCode::CREATED, Json(group)).into_response()
        }
    }
}

pub async fn scim_patch_group(
    Path((_tenant_id_str, group_id)): Path<(String, String)>,
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
    Json(patch): Json<ScimPatch>,
) -> impl IntoResponse {
    let tenant_id = match extract_tenant_from_token(&state, &headers).await {
        Ok(t) => t,
        Err(e) => return e.into_response(),
    };
    match state.scim_service.patch_group(tenant_id, &group_id, patch).await {
        Ok(group) => (StatusCode::OK, Json(group)).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ScimError::new(500, &e.to_string()))).into_response(),
    }
}

pub async fn scim_delete_group(
    Path((_tenant_id_str, group_id)): Path<(String, String)>,
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let tenant_id = match extract_tenant_from_token(&state, &headers).await {
        Ok(t) => t,
        Err(e) => return e.into_response(),
    };
    // Remove all memberships for this role
    let _ = sqlx::query(
        "DELETE FROM core_mdm.tenant_memberships WHERE tenant_id=$1 AND role=$2",
    )
    .bind(tenant_id)
    .bind(&group_id)
    .execute(&state.db)
    .await;

    StatusCode::NO_CONTENT.into_response()
}

// â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

fn display_name_to_role(name: &str) -> String {
    match name.to_lowercase().as_str() {
        n if n.contains("admin") => "admin".to_string(),
        n if n.contains("business") => "business_admin".to_string(),
        n if n.contains("steward") => "steward".to_string(),
        n if n.contains("analyst") => "analyst".to_string(),
        n if n.contains("viewer") => "viewer".to_string(),
        other => other.to_lowercase().replace(' ', "_"),
    }
}

async fn get_default_role(state: &Arc<AppState>, tenant_id: Uuid) -> String {
    let role: Option<String> = sqlx::query_scalar(
        "SELECT default_role FROM core_mdm.sso_configurations WHERE tenant_id=$1 LIMIT 1",
    )
    .bind(tenant_id)
    .fetch_optional(&state.db)
    .await
    .ok()
    .flatten();
    role.unwrap_or_else(|| "steward".to_string())
}
