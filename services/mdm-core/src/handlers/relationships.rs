use std::sync::Arc;

use axum::{
    extract::{Extension, Path, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::handlers::ApiResponse;
use crate::middleware::tenant::TenantContext;
use crate::services::audit_service::AuditEvent;
use crate::AppState;

// ─────────────────────────────────────────────────────────────────────────────
// REQUEST TYPES
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct CreateRelationshipTypeRequest {
    pub name:             String,
    pub display_name:     String,
    pub from_entity_type: String,
    pub to_entity_type:   String,
    pub is_bidirectional: bool,
    pub description:      Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct CreateEntityRelationshipRequest {
    pub type_id:      Uuid,
    pub to_entity_id: Uuid,
    pub strength:     Option<f32>,
    pub attributes:   Option<serde_json::Value>,
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /relationship-types
// ─────────────────────────────────────────────────────────────────────────────

pub async fn list_relationship_types(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    match state
        .relationship_service
        .list_types(tenant_ctx.tenant_id)
        .await
    {
        Ok(types) => (
            StatusCode::OK,
            Json(ApiResponse {
                success: true,
                data:    Some(types),
                error:   None,
            }),
        )
            .into_response(),

        Err(err) => {
            tracing::error!(error=?err, "list_relationship_types failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<Vec<serde_json::Value>> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
                .into_response()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /relationship-types
// ─────────────────────────────────────────────────────────────────────────────

pub async fn create_relationship_type(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Json(req):             Json<CreateRelationshipTypeRequest>,
) -> impl IntoResponse {
    if req.name.trim().is_empty() || req.display_name.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<serde_json::Value> {
                success: false,
                data:    None,
                error:   Some("name and display_name are required".to_string()),
            }),
        )
            .into_response();
    }

    match state
        .relationship_service
        .create_type(
            tenant_ctx.tenant_id,
            &req.name,
            &req.display_name,
            &req.from_entity_type,
            &req.to_entity_type,
            req.is_bidirectional,
            req.description.as_deref(),
        )
        .await
    {
        Ok(type_id) => {
            let actor_id = headers
                .get("x-user-id")
                .and_then(|v| v.to_str().ok())
                .and_then(|s| Uuid::parse_str(s).ok());
            state.audit_service.log_background(AuditEvent {
                tenant_id:     tenant_ctx.tenant_id,
                event_type:    "relationship_type.created".to_string(),
                actor_id,
                resource_type: "relationship_type".to_string(),
                resource_id:   type_id.to_string(),
                metadata:      json!({ "name": req.name, "from": req.from_entity_type, "to": req.to_entity_type }),
                before:        None,
                after:         None,
            });
            (
                StatusCode::CREATED,
                Json(ApiResponse {
                    success: true,
                    data:    Some(json!({ "type_id": type_id })),
                    error:   None,
                }),
            )
                .into_response()
        }

        Err(err) => {
            tracing::error!(error=?err, "create_relationship_type failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
                .into_response()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /relationship-types/:type_id
// ─────────────────────────────────────────────────────────────────────────────

pub async fn delete_relationship_type(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Path(type_id):         Path<Uuid>,
) -> impl IntoResponse {
    match state
        .relationship_service
        .delete_type(tenant_ctx.tenant_id, type_id)
        .await
    {
        Ok(true) => {
            let actor_id = headers
                .get("x-user-id")
                .and_then(|v| v.to_str().ok())
                .and_then(|s| Uuid::parse_str(s).ok());
            state.audit_service.log_background(AuditEvent {
                tenant_id:     tenant_ctx.tenant_id,
                event_type:    "relationship_type.deleted".to_string(),
                actor_id,
                resource_type: "relationship_type".to_string(),
                resource_id:   type_id.to_string(),
                metadata:      json!({}),
                before:        None,
                after:         None,
            });
            (
                StatusCode::OK,
                Json(ApiResponse::<serde_json::Value> {
                    success: true,
                    data:    None,
                    error:   None,
                }),
            )
                .into_response()
        }

        Ok(false) => (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<serde_json::Value> {
                success: false,
                data:    None,
                error:   Some("relationship type not found".to_string()),
            }),
        )
            .into_response(),

        Err(err) => {
            let msg = err.to_string();
            // Service signals system-type protection via a well-known prefix.
            if msg.contains("cannot delete a system relationship type") {
                return (
                    StatusCode::CONFLICT,
                    Json(ApiResponse::<serde_json::Value> {
                        success: false,
                        data:    None,
                        error:   Some(msg),
                    }),
                )
                    .into_response();
            }

            tracing::error!(error=?err, "delete_relationship_type failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(msg),
                }),
            )
                .into_response()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /entities/:id/relationships
// ─────────────────────────────────────────────────────────────────────────────

pub async fn list_entity_relationships(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
) -> impl IntoResponse {
    match state
        .relationship_service
        .list_for_entity(tenant_ctx.tenant_id, entity_id)
        .await
    {
        Ok(relationships) => (
            StatusCode::OK,
            Json(ApiResponse {
                success: true,
                data:    Some(relationships),
                error:   None,
            }),
        )
            .into_response(),

        Err(err) => {
            tracing::error!(error=?err, entity_id=%entity_id, "list_entity_relationships failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<Vec<serde_json::Value>> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
                .into_response()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /entities/:id/relationships
// ─────────────────────────────────────────────────────────────────────────────

pub async fn create_entity_relationship(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Path(from_entity_id):  Path<Uuid>,
    Json(req):             Json<CreateEntityRelationshipRequest>,
) -> impl IntoResponse {
    let strength   = req.strength.unwrap_or(1.0);
    let attributes = req.attributes.unwrap_or(json!({}));

    match state
        .relationship_service
        .create(
            tenant_ctx.tenant_id,
            req.type_id,
            from_entity_id,
            req.to_entity_id,
            strength,
            attributes,
            None, // created_by: caller can extend later via header extraction
        )
        .await
    {
        Ok(relationship_id) => {
            let actor_id = headers
                .get("x-user-id")
                .and_then(|v| v.to_str().ok())
                .and_then(|s| Uuid::parse_str(s).ok());
            state.audit_service.log_background(AuditEvent {
                tenant_id:     tenant_ctx.tenant_id,
                event_type:    "entity_relationship.created".to_string(),
                actor_id,
                resource_type: "relationship".to_string(),
                resource_id:   relationship_id.to_string(),
                metadata:      json!({ "from_entity_id": from_entity_id, "to_entity_id": req.to_entity_id, "type_id": req.type_id }),
                before:        None,
                after:         None,
            });
            (
                StatusCode::CREATED,
                Json(ApiResponse {
                    success: true,
                    data:    Some(json!({ "relationship_id": relationship_id })),
                    error:   None,
                }),
            )
                .into_response()
        }

        Err(err) => {
            tracing::error!(error=?err, from_entity_id=%from_entity_id, "create_entity_relationship failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
                .into_response()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /relationships/:id
// ─────────────────────────────────────────────────────────────────────────────

pub async fn delete_entity_relationship(
    State(state):           State<Arc<AppState>>,
    Extension(tenant_ctx):  Extension<TenantContext>,
    headers:                HeaderMap,
    Path(relationship_id):  Path<Uuid>,
) -> impl IntoResponse {
    match state
        .relationship_service
        .delete(tenant_ctx.tenant_id, relationship_id)
        .await
    {
        Ok(true) => {
            let actor_id = headers
                .get("x-user-id")
                .and_then(|v| v.to_str().ok())
                .and_then(|s| Uuid::parse_str(s).ok());
            state.audit_service.log_background(AuditEvent {
                tenant_id:     tenant_ctx.tenant_id,
                event_type:    "entity_relationship.deleted".to_string(),
                actor_id,
                resource_type: "relationship".to_string(),
                resource_id:   relationship_id.to_string(),
                metadata:      json!({}),
                before:        None,
                after:         None,
            });
            (
                StatusCode::OK,
                Json(ApiResponse::<serde_json::Value> {
                    success: true,
                    data:    None,
                    error:   None,
                }),
            )
                .into_response()
        }

        Ok(false) => (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<serde_json::Value> {
                success: false,
                data:    None,
                error:   Some("relationship not found".to_string()),
            }),
        )
            .into_response(),

        Err(err) => {
            tracing::error!(error=?err, relationship_id=%relationship_id, "delete_entity_relationship failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
                .into_response()
        }
    }
}
