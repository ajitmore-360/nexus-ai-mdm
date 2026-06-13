use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Extension,
    Json,
};
use serde::Deserialize;
use tracing::error;
use uuid::Uuid;

use contracts::mdm::distribution::{CreateEntityRequest, CreateEntityResponse};
use contracts::mdm::entity::{EntityStatus, EntityType};
use database::RequestContext;

use crate::handlers::ApiResponse;
use crate::middleware::tenant::TenantContext;
use crate::AppState;

// ── Query params for GET /entities ──────────────────────────────────────────

#[allow(dead_code)]
#[derive(Deserialize)]
pub struct ListEntitiesParams {
    pub page:          Option<i64>,
    pub page_size:     Option<i64>,
    pub search:        Option<String>,
    #[serde(rename = "type")]
    pub entity_type:   Option<String>,
    pub status:        Option<String>,
    pub source_system: Option<String>,
}

pub async fn create_entity(
    State(state):              State<Arc<AppState>>,
    Extension(tenant_ctx):     Extension<TenantContext>,
    headers:                   HeaderMap,
    Json(request):             Json<CreateEntityRequest>,
) -> impl IntoResponse {
    let ctx = extract_request_context(&tenant_ctx, &headers);

    match state.entity_service.create_entity(ctx, request).await {
        Ok(response) => (
            StatusCode::CREATED,
            Json(ApiResponse {
                success: true,
                data:    Some(response),
                error:   None,
            }),
        ),
        Err(err) => {
            error!(error=?err, "entity creation failed");
            (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<CreateEntityResponse> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
        }
    }
}

/// Build a `RequestContext` from inbound HTTP headers.
///
/// Falls back to new UUIDs / empty strings when optional headers are absent
/// so every request has a complete, traceable context regardless of the caller.
pub(crate) fn extract_request_context(
    tenant_ctx: &TenantContext,
    headers:    &HeaderMap,
) -> RequestContext {
    let user_id = headers
        .get("x-user-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok());

    let trace_id = headers
        .get("x-trace-id")
        .or_else(|| headers.get("traceparent"))
        .and_then(|v| v.to_str().ok())
        .map(str::to_owned)
        .unwrap_or_else(|| Uuid::new_v4().to_string());

    RequestContext::new(tenant_ctx.tenant_id, user_id, trace_id)
}

// ── GET /entities — paginated list ──────────────────────────────────────────

pub async fn list_entities(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params):         Query<ListEntitiesParams>,
) -> impl IntoResponse {
    let page      = params.page.unwrap_or(1).max(1);
    let page_size = params.page_size.unwrap_or(20).clamp(1, 100);

    match state
        .entity_repository
        .list_entities(
            tenant_ctx.tenant_id,
            page,
            page_size,
            params.entity_type.as_deref(),
            params.status.as_deref(),
            params.search.as_deref(),
        )
        .await
    {
        Ok((items, total_count)) => (
            StatusCode::OK,
            Json(serde_json::json!({
                "items":       items,
                "page":        page,
                "page_size":   page_size,
                "total_count": total_count
            })),
        )
            .into_response(),
        Err(err) => {
            error!(error=?err, "list_entities failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error":   "failed to list entities"
                })),
            )
                .into_response()
        }
    }
}

// ── GET /entities/:id — single entity ───────────────────────────────────────

pub async fn get_entity_by_id(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<String>,
) -> impl IntoResponse {
    let entity_uuid = match Uuid::parse_str(&entity_id) {
        Ok(id)  => id,
        Err(_)  => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({ "success": false, "error": "invalid entity id" })),
            )
                .into_response();
        }
    };

    match state
        .entity_repository
        .fetch_entity(tenant_ctx.tenant_id, entity_uuid)
        .await
    {
        Ok(Some(entity)) => {
            let flutter_type   = entity_type_to_flutter_type(&entity.entity_type);
            let flutter_status = entity_status_to_flutter_status(&entity.status);

            // Derive display_name from the first recognisable name attribute.
            let display_name = entity
                .attributes
                .iter()
                .find(|a| {
                    ["name", "full_name", "display_name", "company_name", "legal_name"]
                        .contains(&a.key.to_lowercase().as_str())
                })
                .and_then(|a| a.value.as_str().map(str::to_owned))
                .unwrap_or_else(|| {
                    format!("{:?} {}", entity.entity_type, &entity.entity_id.to_string()[..8])
                });

            // Derive primary_source from the first attribute that has one set.
            // (The entity_attributes table stores source_system as a flat text column;
            //  the Rust contracts model maps it via provenance which may be None.)
            let primary_source = entity
                .attributes
                .iter()
                .find_map(|a| a.provenance.as_ref().map(|p| p.source.source_system.clone()))
                .unwrap_or_else(|| {
                    // Fallback: check entity-level source_system from external_ids keys.
                    entity
                        .external_ids
                        .keys()
                        .next()
                        .cloned()
                        .unwrap_or_else(|| "Nexus MDM".to_string())
                });

            let source_systems: Vec<String> = {
                let mut seen = std::collections::HashSet::new();
                entity
                    .attributes
                    .iter()
                    .filter_map(|a| {
                        a.provenance
                            .as_ref()
                            .map(|p| p.source.source_system.clone())
                    })
                    .filter(|s| seen.insert(s.clone()))
                    .collect()
            };
            let source_systems = if source_systems.is_empty() {
                vec![primary_source.clone()]
            } else {
                source_systems
            };

            // Build the attributes map (keyed by attribute_key).
            let attributes: serde_json::Map<String, serde_json::Value> = entity
                .attributes
                .iter()
                .map(|attr| {
                    let source_sys = attr
                        .provenance
                        .as_ref()
                        .map(|p| p.source.source_system.as_str())
                        .unwrap_or("Unknown");
                    let confidence =
                        attr.confidence.as_ref().map(|c| c.score as f64).unwrap_or(0.0);
                    let updated_at = attr
                        .updated_at
                        .map(|t| t.to_rfc3339())
                        .unwrap_or_default();

                    let attr_json = serde_json::json!({
                        "name":         attr.key,
                        "display_name": attr.key,
                        "value":        attr.value,
                        "source_system": source_sys,
                        "confidence":   confidence,
                        "has_conflict": false,
                        "conflicts":    [],
                        "updated_at":   updated_at
                    });
                    (attr.key.clone(), attr_json)
                })
                .collect();

            let trust = entity.trust_score.map(|s| s as f64).unwrap_or(0.8);

            let json = serde_json::json!({
                "id":             entity.entity_id.to_string(),
                "entity_id":      entity.entity_id.to_string(),
                "type":           flutter_type,
                "status":         flutter_status,
                "display_name":   display_name,
                "trust_score":    trust,
                "quality_score":  trust,
                "primary_source": primary_source,
                "source_systems": source_systems,
                "attributes":     attributes,
                "created_at":     entity.audit.created_at.to_rfc3339(),
                "updated_at":     entity.audit.updated_at.to_rfc3339()
            });

            (StatusCode::OK, Json(json)).into_response()
        }
        Ok(None) => (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({ "success": false, "error": "entity not found" })),
        )
            .into_response(),
        Err(err) => {
            error!(error=?err, "fetch_entity failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "success": false, "error": "failed to fetch entity" })),
            )
                .into_response()
        }
    }
}

// ── PATCH /entities/:id — partial entity update ──────────────────────────────

#[derive(serde::Deserialize)]
pub struct PatchEntityRequest {
    pub entity_type: Option<String>,
    pub status:      Option<String>,
    pub tags:        Option<Vec<String>>,
    pub attributes:  Option<Vec<contracts::mdm::entity::EntityAttribute>>,
}

pub async fn patch_entity(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<String>,
    Json(request):         Json<PatchEntityRequest>,
) -> impl IntoResponse {
    let entity_uuid = match Uuid::parse_str(&entity_id) {
        Ok(id)  => id,
        Err(_)  => return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "success": false, "error": "invalid entity id" })),
        ).into_response(),
    };

    let mut tx = match state.db.begin().await {
        Ok(t)  => t,
        Err(e) => {
            error!(error=?e, "failed to begin transaction");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "success": false, "error": "transaction error" })),
            ).into_response();
        }
    };

    match state.entity_repository.update_entity(
        &mut tx,
        tenant_ctx.tenant_id,
        entity_uuid,
        request.entity_type.as_deref(),
        request.status.as_deref(),
        request.tags.as_ref(),
        request.attributes.as_ref(),
    ).await {
        Ok(true) => {
            if let Err(e) = tx.commit().await {
                error!(error=?e, "commit failed");
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(serde_json::json!({ "success": false, "error": "commit failed" })),
                ).into_response();
            }
            (StatusCode::OK, Json(serde_json::json!({
                "success": true,
                "entity_id": entity_uuid.to_string()
            }))).into_response()
        }
        Ok(false) => (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({ "success": false, "error": "entity not found" })),
        ).into_response(),
        Err(e) => {
            error!(error=?e, "update_entity failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "success": false, "error": "failed to update entity" })),
            ).into_response()
        }
    }
}

// ── Local type-mapping helpers (use string variants from DB) ─────────────────

fn entity_type_to_flutter_type(et: &EntityType) -> &'static str {
    match et {
        EntityType::Customer | EntityType::Employee                     => "person",
        EntityType::Vendor   | EntityType::Account | EntityType::Organization => "organization",
        EntityType::Material | EntityType::Product | EntityType::ReferenceData => "product",
        EntityType::Location                                            => "location",
        EntityType::Asset                                               => "asset",
        EntityType::Custom(_)                                           => "person",
    }
}

fn entity_status_to_flutter_status(es: &EntityStatus) -> &'static str {
    match es {
        EntityStatus::Active                                              => "active",
        EntityStatus::Draft                                               => "pending",
        EntityStatus::PendingReview | EntityStatus::UnderInvestigation   => "review",
        EntityStatus::Merged                                              => "merged",
        EntityStatus::Inactive | EntityStatus::Deleted
        | EntityStatus::Archived | EntityStatus::SoftDeleted             => "inactive",
    }
}
