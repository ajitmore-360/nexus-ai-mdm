use std::sync::Arc;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    Extension, Json,
};
use serde::Deserialize;
use serde_json::json;
use sqlx::Row;
use uuid::Uuid;

use azile_auth::Role;

use crate::middleware::tenant::TenantContext;
use crate::services::audit_service::AuditEvent;
use crate::AppState;

// â"€â"€ Shared response helper â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

fn ok(data: serde_json::Value) -> Response {
    (StatusCode::OK, Json(json!({ "success": true, "data": data }))).into_response()
}

fn created(data: serde_json::Value) -> Response {
    (StatusCode::CREATED, Json(json!({ "success": true, "data": data }))).into_response()
}

fn err(status: StatusCode, msg: &str) -> Response {
    (status, Json(json!({ "success": false, "error": msg }))).into_response()
}

// â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
// ASSIGNMENT CRUD
// â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

#[derive(Debug, Deserialize)]
pub struct CreateAssignmentRequest {
    pub identity_id:      Uuid,
    pub entity_type_code: String,
    pub assignment_type:  String, // "owner" | "steward"
}

/// GET /governance/assignments â€" list all assignments for this tenant.
/// Required role: BusinessAdmin or Admin.
pub async fn list_assignments(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Extension(claims):     Extension<azile_auth::Claims>,
) -> Response {
    if !claims.nxs_role.can_admin() {
        return err(StatusCode::FORBIDDEN, "admin or business_admin role required");
    }

    let rows = sqlx::query(
        r#"
        SELECT a.assignment_id, a.entity_type_code, a.assignment_type, a.assigned_at,
               i.identity_id, i.email, i.display_name
        FROM   core_mdm.entity_type_assignments a
        JOIN   core_mdm.identities i ON i.identity_id = a.identity_id
        WHERE  a.tenant_id = $1
        ORDER  BY a.entity_type_code, a.assignment_type, i.display_name
        "#,
    )
    .bind(tenant_ctx.tenant_id)
    .fetch_all(&state.db)
    .await;

    match rows {
        Ok(rows) => {
            let items: Vec<serde_json::Value> = rows.iter().map(|r| {
                json!({
                    "assignment_id":    r.get::<Uuid, _>("assignment_id"),
                    "entity_type_code": r.get::<String, _>("entity_type_code"),
                    "assignment_type":  r.get::<String, _>("assignment_type"),
                    "assigned_at":      r.get::<chrono::DateTime<chrono::Utc>, _>("assigned_at"),
                    "identity_id":      r.get::<Uuid, _>("identity_id"),
                    "email":            r.get::<String, _>("email"),
                    "display_name":     r.get::<Option<String>, _>("display_name"),
                })
            }).collect();
            ok(json!(items))
        }
        Err(e) => {
            tracing::error!(error=?e, "list_assignments failed");
            err(StatusCode::INTERNAL_SERVER_ERROR, "failed to list assignments")
        }
    }
}

/// GET /governance/assignments/my-types â€" list entity types the calling user is assigned to.
/// Used by Steward-role users to know what they can access.
pub async fn my_assigned_types(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Extension(claims):     Extension<azile_auth::Claims>,
) -> Response {
    let identity_id = match Uuid::parse_str(&claims.sub) {
        Ok(id) => id,
        Err(_) => return err(StatusCode::UNAUTHORIZED, "invalid identity in token"),
    };

    let rows = sqlx::query(
        r#"
        SELECT entity_type_code, assignment_type
        FROM   core_mdm.entity_type_assignments
        WHERE  tenant_id = $1 AND identity_id = $2
        ORDER  BY entity_type_code
        "#,
    )
    .bind(tenant_ctx.tenant_id)
    .bind(identity_id)
    .fetch_all(&state.db)
    .await;

    match rows {
        Ok(rows) => {
            let items: Vec<serde_json::Value> = rows.iter().map(|r| {
                json!({
                    "entity_type_code": r.get::<String, _>("entity_type_code"),
                    "assignment_type":  r.get::<String, _>("assignment_type"),
                })
            }).collect();
            ok(json!(items))
        }
        Err(e) => {
            tracing::error!(error=?e, "my_assigned_types failed");
            err(StatusCode::INTERNAL_SERVER_ERROR, "failed to fetch assigned types")
        }
    }
}

/// POST /governance/assignments â€" create an entity-type assignment.
/// Required role: BusinessAdmin or Admin.
pub async fn create_assignment(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Extension(claims):     Extension<azile_auth::Claims>,
    Json(req):             Json<CreateAssignmentRequest>,
) -> Response {
    if !claims.nxs_role.can_admin() {
        return err(StatusCode::FORBIDDEN, "admin or business_admin role required");
    }
    if req.assignment_type != "owner" && req.assignment_type != "steward" {
        return err(StatusCode::BAD_REQUEST, "assignment_type must be 'owner' or 'steward'");
    }

    let assigner_id = Uuid::parse_str(&claims.sub).ok();

    let result = sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO core_mdm.entity_type_assignments
               (tenant_id, identity_id, entity_type_code, assignment_type, assigned_by)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (tenant_id, identity_id, entity_type_code)
        DO UPDATE SET assignment_type = EXCLUDED.assignment_type,
                      assigned_by     = EXCLUDED.assigned_by,
                      assigned_at     = now()
        RETURNING assignment_id
        "#,
    )
    .bind(tenant_ctx.tenant_id)
    .bind(req.identity_id)
    .bind(&req.entity_type_code)
    .bind(&req.assignment_type)
    .bind(assigner_id)
    .fetch_one(&state.db)
    .await;

    match result {
        Ok(id) => created(json!({ "assignment_id": id })),
        Err(e) => {
            let msg = e.to_string();
            if msg.contains("entity_type_assignments_one_owner_idx") {
                return err(
                    StatusCode::CONFLICT,
                    "this entity type already has a Data Owner â€" remove the existing owner first",
                );
            }
            tracing::error!(error=?e, "create_assignment failed");
            err(StatusCode::INTERNAL_SERVER_ERROR, "failed to create assignment")
        }
    }
}

/// DELETE /governance/assignments/:id â€" remove an assignment.
/// Required role: BusinessAdmin or Admin.
pub async fn delete_assignment(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Extension(claims):     Extension<azile_auth::Claims>,
    Path(assignment_id):   Path<Uuid>,
) -> Response {
    if !claims.nxs_role.can_admin() {
        return err(StatusCode::FORBIDDEN, "admin or business_admin role required");
    }

    let result = sqlx::query(
        "DELETE FROM core_mdm.entity_type_assignments WHERE assignment_id = $1 AND tenant_id = $2",
    )
    .bind(assignment_id)
    .bind(tenant_ctx.tenant_id)
    .execute(&state.db)
    .await;

    match result {
        Ok(r) if r.rows_affected() == 0 => err(StatusCode::NOT_FOUND, "assignment not found"),
        Ok(_)  => ok(json!({ "deleted": true })),
        Err(e) => {
            tracing::error!(error=?e, "delete_assignment failed");
            err(StatusCode::INTERNAL_SERVER_ERROR, "failed to delete assignment")
        }
    }
}

// â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
// APPROVAL WORKFLOW
// â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

#[derive(Debug, Deserialize)]
pub struct SubmitForReviewRequest {
    pub change_summary: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct RejectEntityRequest {
    pub reviewer_notes: String,
}

/// POST /entities/:id/submit-for-review
/// Steward submits an entity for Data Owner approval.
/// Sets entity status to PendingReview and creates an approval request.
pub async fn submit_for_review(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Extension(claims):     Extension<azile_auth::Claims>,
    Path(entity_id):       Path<Uuid>,
    Json(req):             Json<SubmitForReviewRequest>,
) -> Response {
    let identity_id = match Uuid::parse_str(&claims.sub) {
        Ok(id) => id,
        Err(_) => return err(StatusCode::UNAUTHORIZED, "invalid identity in token"),
    };

    // Load entity â€" verify it belongs to this tenant
    let entity_row = sqlx::query(
        "SELECT entity_id, entity_type, status FROM core_mdm.entities WHERE entity_id = $1 AND tenant_id = $2",
    )
    .bind(entity_id)
    .bind(tenant_ctx.tenant_id)
    .fetch_optional(&state.db)
    .await;

    let entity_row = match entity_row {
        Ok(Some(r)) => r,
        Ok(None)    => return err(StatusCode::NOT_FOUND, "entity not found"),
        Err(e)      => {
            tracing::error!(error=?e, "submit_for_review entity lookup failed");
            return err(StatusCode::INTERNAL_SERVER_ERROR, "database error");
        }
    };

    let entity_type: String = entity_row.get("entity_type");
    let current_status: String = entity_row.get("status");

    if current_status == "PendingReview" {
        return err(StatusCode::CONFLICT, "entity is already pending review");
    }
    if current_status == "Active" && !claims.nxs_role.can_admin() {
        return err(StatusCode::CONFLICT, "entity is already published");
    }

    // For Steward role: verify they're assigned to this entity type
    if claims.nxs_role == Role::Steward {
        let assigned: Option<bool> = sqlx::query_scalar(
            "SELECT TRUE FROM core_mdm.entity_type_assignments WHERE tenant_id=$1 AND identity_id=$2 AND entity_type_code=$3"
        )
        .bind(tenant_ctx.tenant_id)
        .bind(identity_id)
        .bind(&entity_type)
        .fetch_optional(&state.db)
        .await
        .unwrap_or(None);

        if assigned.is_none() {
            return err(StatusCode::FORBIDDEN, "you are not assigned to this entity type");
        }
    }

    // Transition entity to PendingReview
    let update = sqlx::query(
        "UPDATE core_mdm.entities SET status = 'PendingReview', updated_at = now() WHERE entity_id = $1 AND tenant_id = $2",
    )
    .bind(entity_id)
    .bind(tenant_ctx.tenant_id)
    .execute(&state.db)
    .await;

    if let Err(e) = update {
        tracing::error!(error=?e, "submit_for_review status update failed");
        return err(StatusCode::INTERNAL_SERVER_ERROR, "failed to update entity status");
    }

    // Create approval request (upsert: cancel any prior rejected request for this entity)
    let request_id = sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO core_mdm.entity_approval_requests
               (tenant_id, entity_id, entity_type_code, submitted_by, change_summary)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING request_id
        "#,
    )
    .bind(tenant_ctx.tenant_id)
    .bind(entity_id)
    .bind(&entity_type)
    .bind(identity_id)
    .bind(req.change_summary.as_deref())
    .fetch_one(&state.db)
    .await;

    let request_id = match request_id {
        Ok(id) => id,
        Err(e) => {
            tracing::error!(error=?e, "submit_for_review insert failed");
            return err(StatusCode::INTERNAL_SERVER_ERROR, "failed to create approval request");
        }
    };

    // Notify the Data Owner for this entity type
    if let Ok(Some(owner_id)) = sqlx::query_scalar::<_, Uuid>(
        "SELECT identity_id FROM core_mdm.entity_type_assignments WHERE tenant_id=$1 AND entity_type_code=$2 AND assignment_type='owner'"
    )
    .bind(tenant_ctx.tenant_id)
    .bind(&entity_type)
    .fetch_optional(&state.db)
    .await {
        state.notification_service.notify(
            tenant_ctx.tenant_id,
            Some(owner_id),
            "entity.pending_review",
            &format!("{} record needs your approval", entity_type),
            &format!("A {} record has been submitted for your review. Entity ID: {}", entity_type, entity_id),
            "info",
            json!({ "entity_id": entity_id, "request_id": request_id, "entity_type": entity_type }),
        ).await.ok();
    }

    state.audit_service.log_background(AuditEvent {
        tenant_id:     tenant_ctx.tenant_id,
        event_type:    "entity.submitted_for_review".to_string(),
        actor_id:      Some(identity_id),
        resource_type: "entity".to_string(),
        resource_id:   entity_id.to_string(),
        metadata:      json!({ "entity_id": entity_id, "request_id": request_id, "entity_type": entity_type }),
        before:        None,
        after:         None,
    });

    tracing::info!(
        entity_id=%entity_id,
        submitted_by=%identity_id,
        entity_type=%entity_type,
        "entity submitted for review"
    );

    ok(json!({
        "request_id": request_id,
        "entity_id":  entity_id,
        "status":     "pending",
    }))
}

/// GET /entities/pending-approvals â€" returns entities awaiting the caller's approval.
/// Data Owners see entities of their owned type. Admins/BusinessAdmins see all pending.
pub async fn list_pending_approvals(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Extension(claims):     Extension<azile_auth::Claims>,
) -> Response {
    let identity_id = Uuid::parse_str(&claims.sub).unwrap_or(Uuid::nil());

    // Determine which entity types this user can approve:
    // - Admin/BusinessAdmin: all types
    // - Steward with 'owner' assignment: their owned types only
    let rows = if claims.nxs_role.can_admin() {
        sqlx::query(
            r#"
            SELECT r.request_id, r.entity_id, r.entity_type_code, r.submitted_at,
                   r.change_summary, r.status,
                   i.display_name AS submitter_name, i.email AS submitter_email
            FROM   core_mdm.entity_approval_requests r
            JOIN   core_mdm.identities i ON i.identity_id = r.submitted_by
            WHERE  r.tenant_id = $1 AND r.status = 'pending'
            ORDER  BY r.submitted_at ASC
            "#,
        )
        .bind(tenant_ctx.tenant_id)
        .fetch_all(&state.db)
        .await
    } else {
        sqlx::query(
            r#"
            SELECT r.request_id, r.entity_id, r.entity_type_code, r.submitted_at,
                   r.change_summary, r.status,
                   i.display_name AS submitter_name, i.email AS submitter_email
            FROM   core_mdm.entity_approval_requests r
            JOIN   core_mdm.identities i ON i.identity_id = r.submitted_by
            JOIN   core_mdm.entity_type_assignments a
                   ON  a.tenant_id        = r.tenant_id
                   AND a.entity_type_code = r.entity_type_code
                   AND a.identity_id      = $2
                   AND a.assignment_type  = 'owner'
            WHERE  r.tenant_id = $1 AND r.status = 'pending'
            ORDER  BY r.submitted_at ASC
            "#,
        )
        .bind(tenant_ctx.tenant_id)
        .bind(identity_id)
        .fetch_all(&state.db)
        .await
    };

    match rows {
        Ok(rows) => {
            let items: Vec<serde_json::Value> = rows.iter().map(|r| {
                json!({
                    "request_id":       r.get::<Uuid, _>("request_id"),
                    "entity_id":        r.get::<Uuid, _>("entity_id"),
                    "entity_type_code": r.get::<String, _>("entity_type_code"),
                    "submitted_at":     r.get::<chrono::DateTime<chrono::Utc>, _>("submitted_at"),
                    "change_summary":   r.get::<Option<String>, _>("change_summary"),
                    "status":           r.get::<String, _>("status"),
                    "submitter_name":   r.get::<Option<String>, _>("submitter_name"),
                    "submitter_email":  r.get::<String, _>("submitter_email"),
                })
            }).collect();
            ok(json!(items))
        }
        Err(e) => {
            tracing::error!(error=?e, "list_pending_approvals failed");
            err(StatusCode::INTERNAL_SERVER_ERROR, "failed to list pending approvals")
        }
    }
}

/// POST /entities/:id/approve â€" Data Owner approves an entity and publishes it.
pub async fn approve_entity(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Extension(claims):     Extension<azile_auth::Claims>,
    Path(entity_id):       Path<Uuid>,
) -> Response {
    let identity_id = match Uuid::parse_str(&claims.sub) {
        Ok(id) => id,
        Err(_) => return err(StatusCode::UNAUTHORIZED, "invalid identity in token"),
    };

    // Load the pending approval request
    let req_row = sqlx::query(
        "SELECT request_id, entity_type_code, submitted_by FROM core_mdm.entity_approval_requests WHERE entity_id=$1 AND tenant_id=$2 AND status='pending'"
    )
    .bind(entity_id)
    .bind(tenant_ctx.tenant_id)
    .fetch_optional(&state.db)
    .await;

    let req_row = match req_row {
        Ok(Some(r)) => r,
        Ok(None)    => return err(StatusCode::NOT_FOUND, "no pending approval request for this entity"),
        Err(e)      => {
            tracing::error!(error=?e, "approve_entity lookup failed");
            return err(StatusCode::INTERNAL_SERVER_ERROR, "database error");
        }
    };

    let request_id:       Uuid   = req_row.get("request_id");
    let entity_type_code: String = req_row.get("entity_type_code");
    let submitted_by:     Uuid   = req_row.get("submitted_by");

    // Authorise: must be Admin, BusinessAdmin, or the designated owner for this type
    if !claims.nxs_role.can_admin() {
        let is_owner: Option<bool> = sqlx::query_scalar(
            "SELECT TRUE FROM core_mdm.entity_type_assignments WHERE tenant_id=$1 AND identity_id=$2 AND entity_type_code=$3 AND assignment_type='owner'"
        )
        .bind(tenant_ctx.tenant_id)
        .bind(identity_id)
        .bind(&entity_type_code)
        .fetch_optional(&state.db)
        .await
        .unwrap_or(None);

        if is_owner.is_none() {
            return err(StatusCode::FORBIDDEN, "only the Data Owner for this entity type can approve");
        }
    }

    // Both writes must succeed atomically â€" dropped txn auto-rolls-back on early return.
    let mut txn = match state.db.begin().await {
        Ok(t)  => t,
        Err(e) => {
            tracing::error!(error=?e, "approve_entity begin txn failed");
            return err(StatusCode::INTERNAL_SERVER_ERROR, "database error");
        }
    };

    if let Err(e) = sqlx::query(
        "UPDATE core_mdm.entity_approval_requests SET status='approved', reviewed_by=$1, reviewed_at=now() WHERE request_id=$2"
    )
    .bind(identity_id)
    .bind(request_id)
    .execute(&mut *txn)
    .await {
        tracing::error!(error=?e, "approve_entity update request failed");
        return err(StatusCode::INTERNAL_SERVER_ERROR, "failed to update approval request");
    }

    if let Err(e) = sqlx::query(
        "UPDATE core_mdm.entities SET status='Active', updated_at=now() WHERE entity_id=$1 AND tenant_id=$2"
    )
    .bind(entity_id)
    .bind(tenant_ctx.tenant_id)
    .execute(&mut *txn)
    .await {
        tracing::error!(error=?e, "approve_entity publish failed");
        return err(StatusCode::INTERNAL_SERVER_ERROR, "failed to publish entity");
    }

    if let Err(e) = txn.commit().await {
        tracing::error!(error=?e, "approve_entity commit failed");
        return err(StatusCode::INTERNAL_SERVER_ERROR, "failed to commit approval");
    }

    // Notify the steward who submitted
    state.notification_service.notify(
        tenant_ctx.tenant_id,
        Some(submitted_by),
        "entity.approved",
        &format!("{} record approved", entity_type_code),
        &format!("Your {} record has been approved and published. Entity ID: {}", entity_type_code, entity_id),
        "info",
        json!({ "entity_id": entity_id, "entity_type": entity_type_code }),
    ).await.ok();

    state.audit_service.log_background(AuditEvent {
        tenant_id:     tenant_ctx.tenant_id,
        event_type:    "entity.approved".to_string(),
        actor_id:      Some(identity_id),
        resource_type: "entity".to_string(),
        resource_id:   entity_id.to_string(),
        metadata:      json!({ "entity_id": entity_id, "entity_type": entity_type_code }),
        before:        None,
        after:         None,
    });

    tracing::info!(entity_id=%entity_id, approved_by=%identity_id, "entity approved and published");

    ok(json!({ "entity_id": entity_id, "status": "Active" }))
}

/// POST /entities/:id/reject â€" Data Owner rejects a pending entity with notes.
pub async fn reject_entity(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Extension(claims):     Extension<azile_auth::Claims>,
    Path(entity_id):       Path<Uuid>,
    Json(req):             Json<RejectEntityRequest>,
) -> Response {
    let identity_id = match Uuid::parse_str(&claims.sub) {
        Ok(id) => id,
        Err(_) => return err(StatusCode::UNAUTHORIZED, "invalid identity in token"),
    };

    let req_row = sqlx::query(
        "SELECT request_id, entity_type_code, submitted_by FROM core_mdm.entity_approval_requests WHERE entity_id=$1 AND tenant_id=$2 AND status='pending'"
    )
    .bind(entity_id)
    .bind(tenant_ctx.tenant_id)
    .fetch_optional(&state.db)
    .await;

    let req_row = match req_row {
        Ok(Some(r)) => r,
        Ok(None)    => return err(StatusCode::NOT_FOUND, "no pending approval request for this entity"),
        Err(e)      => {
            tracing::error!(error=?e, "reject_entity lookup failed");
            return err(StatusCode::INTERNAL_SERVER_ERROR, "database error");
        }
    };

    let request_id:       Uuid   = req_row.get("request_id");
    let entity_type_code: String = req_row.get("entity_type_code");
    let submitted_by:     Uuid   = req_row.get("submitted_by");

    if !claims.nxs_role.can_admin() {
        let is_owner: Option<bool> = sqlx::query_scalar(
            "SELECT TRUE FROM core_mdm.entity_type_assignments WHERE tenant_id=$1 AND identity_id=$2 AND entity_type_code=$3 AND assignment_type='owner'"
        )
        .bind(tenant_ctx.tenant_id)
        .bind(identity_id)
        .bind(&entity_type_code)
        .fetch_optional(&state.db)
        .await
        .unwrap_or(None);

        if is_owner.is_none() {
            return err(StatusCode::FORBIDDEN, "only the Data Owner for this entity type can reject");
        }
    }

    let mut txn = match state.db.begin().await {
        Ok(t)  => t,
        Err(e) => {
            tracing::error!(error=?e, "reject_entity begin txn failed");
            return err(StatusCode::INTERNAL_SERVER_ERROR, "database error");
        }
    };

    if let Err(e) = sqlx::query(
        "UPDATE core_mdm.entity_approval_requests SET status='rejected', reviewed_by=$1, reviewed_at=now(), reviewer_notes=$2 WHERE request_id=$3"
    )
    .bind(identity_id)
    .bind(&req.reviewer_notes)
    .bind(request_id)
    .execute(&mut *txn)
    .await {
        tracing::error!(error=?e, "reject_entity update failed");
        return err(StatusCode::INTERNAL_SERVER_ERROR, "failed to update approval request");
    }

    if let Err(e) = sqlx::query(
        "UPDATE core_mdm.entities SET status='Draft', updated_at=now() WHERE entity_id=$1 AND tenant_id=$2"
    )
    .bind(entity_id)
    .bind(tenant_ctx.tenant_id)
    .execute(&mut *txn)
    .await {
        tracing::error!(error=?e, "reject_entity draft reset failed");
        return err(StatusCode::INTERNAL_SERVER_ERROR, "failed to reset entity status");
    }

    if let Err(e) = txn.commit().await {
        tracing::error!(error=?e, "reject_entity commit failed");
        return err(StatusCode::INTERNAL_SERVER_ERROR, "failed to commit rejection");
    }

    // Notify the steward
    state.notification_service.notify(
        tenant_ctx.tenant_id,
        Some(submitted_by),
        "entity.rejected",
        &format!("{} record needs revision", entity_type_code),
        &format!(
            "Your {} record was returned for revision. Notes: {}",
            entity_type_code, req.reviewer_notes
        ),
        "warning",
        json!({ "entity_id": entity_id, "entity_type": entity_type_code, "notes": req.reviewer_notes }),
    ).await.ok();

    state.audit_service.log_background(AuditEvent {
        tenant_id:     tenant_ctx.tenant_id,
        event_type:    "entity.rejected".to_string(),
        actor_id:      Some(identity_id),
        resource_type: "entity".to_string(),
        resource_id:   entity_id.to_string(),
        metadata:      json!({
            "entity_id":      entity_id,
            "entity_type":    entity_type_code,
            "reviewer_notes": req.reviewer_notes,
        }),
        before:        None,
        after:         None,
    });

    tracing::info!(entity_id=%entity_id, rejected_by=%identity_id, "entity rejected, returned to draft");

    ok(json!({ "entity_id": entity_id, "status": "Draft", "reviewer_notes": req.reviewer_notes }))
}

// â"€â"€ Bulk entity actions â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

#[derive(Deserialize)]
pub struct BulkEntityActionRequest {
    pub entity_ids:     Vec<Uuid>,
    pub reviewer_notes: Option<String>,
}

/// POST /entities/bulk-approve â€" approve multiple pending entities in one call.
///
/// Returns a summary with `succeeded`, `skipped` (no pending request, or
/// caller lacks permission for that type), and `failed` (DB error) entity IDs.
pub async fn bulk_approve_entities(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Extension(claims):     Extension<azile_auth::Claims>,
    Json(req):             Json<BulkEntityActionRequest>,
) -> Response {
    let identity_id = match Uuid::parse_str(&claims.sub) {
        Ok(id) => id,
        Err(_) => return err(StatusCode::UNAUTHORIZED, "invalid identity in token"),
    };

    if req.entity_ids.is_empty() {
        return err(StatusCode::BAD_REQUEST, "entity_ids must not be empty");
    }

    // Fetch all pending approval requests for the given entity IDs in one query.
    let pending = match sqlx::query(
        "SELECT request_id, entity_id, entity_type_code, submitted_by
         FROM core_mdm.entity_approval_requests
         WHERE entity_id = ANY($1) AND tenant_id = $2 AND status = 'pending'",
    )
    .bind(&req.entity_ids)
    .bind(tenant_ctx.tenant_id)
    .fetch_all(&state.db)
    .await {
        Ok(rows) => rows,
        Err(e) => {
            tracing::error!(error=?e, "bulk_approve_entities fetch failed");
            return err(StatusCode::INTERNAL_SERVER_ERROR, "database error");
        }
    };

    // For non-admins, restrict to types they own.
    let owned_types: Option<Vec<String>> = if claims.nxs_role.can_admin() {
        None
    } else {
        Some(
            sqlx::query_scalar::<_, String>(
                "SELECT entity_type_code FROM core_mdm.entity_type_assignments
                 WHERE tenant_id=$1 AND identity_id=$2 AND assignment_type='owner'",
            )
            .bind(tenant_ctx.tenant_id)
            .bind(identity_id)
            .fetch_all(&state.db)
            .await
            .unwrap_or_default(),
        )
    };

    let pending_ids: Vec<Uuid> = pending.iter().map(|r| r.get("entity_id")).collect();
    let mut succeeded = Vec::<String>::new();
    let mut skipped   = Vec::<String>::new();
    let mut failed    = Vec::<String>::new();

    for row in &pending {
        let request_id:   Uuid   = row.get("request_id");
        let entity_id:    Uuid   = row.get("entity_id");
        let type_code:    String = row.get("entity_type_code");
        let submitted_by: Uuid   = row.get("submitted_by");

        if let Some(ref owned) = owned_types {
            if !owned.contains(&type_code) {
                skipped.push(entity_id.to_string());
                continue;
            }
        }

        let mut txn = match state.db.begin().await {
            Ok(t)  => t,
            Err(e) => {
                tracing::error!(entity_id=%entity_id, error=?e, "bulk_approve: begin txn failed");
                failed.push(entity_id.to_string());
                continue;
            }
        };

        if sqlx::query(
            "UPDATE core_mdm.entity_approval_requests \
             SET status='approved', reviewed_by=$1, reviewed_at=now() WHERE request_id=$2",
        )
        .bind(identity_id).bind(request_id)
        .execute(&mut *txn).await.is_err() {
            tracing::error!(entity_id=%entity_id, "bulk_approve: request update failed");
            failed.push(entity_id.to_string());
            continue; // txn dropped â†’ auto-rollback
        }

        if sqlx::query(
            "UPDATE core_mdm.entities \
             SET status='Active', updated_at=now() WHERE entity_id=$1 AND tenant_id=$2",
        )
        .bind(entity_id).bind(tenant_ctx.tenant_id)
        .execute(&mut *txn).await.is_err() {
            tracing::error!(entity_id=%entity_id, "bulk_approve: entity publish failed");
            failed.push(entity_id.to_string());
            continue;
        }

        if let Err(e) = txn.commit().await {
            tracing::error!(entity_id=%entity_id, error=?e, "bulk_approve: commit failed");
            failed.push(entity_id.to_string());
            continue;
        }

        state.notification_service.notify(
            tenant_ctx.tenant_id, Some(submitted_by),
            "entity.approved",
            &format!("{} record approved", type_code),
            &format!("Your {} record has been approved and published. Entity ID: {}", type_code, entity_id),
            "info",
            json!({ "entity_id": entity_id, "entity_type": type_code }),
        ).await.ok();

        state.audit_service.log_background(AuditEvent {
            tenant_id:     tenant_ctx.tenant_id,
            event_type:    "entity.approved".to_string(),
            actor_id:      Some(identity_id),
            resource_type: "entity".to_string(),
            resource_id:   entity_id.to_string(),
            metadata:      json!({ "entity_id": entity_id, "entity_type": type_code, "bulk": true }),
            before:        None,
            after:         None,
        });

        succeeded.push(entity_id.to_string());
    }

    // IDs that had no pending request at all.
    for &eid in &req.entity_ids {
        if !pending_ids.contains(&eid) {
            skipped.push(eid.to_string());
        }
    }

    tracing::info!(
        succeeded=%succeeded.len(), skipped=%skipped.len(), failed=%failed.len(),
        "bulk_approve_entities complete"
    );

    ok(json!({ "succeeded": succeeded, "skipped": skipped, "failed": failed }))
}

/// POST /entities/bulk-reject â€" reject multiple pending entities in one call.
pub async fn bulk_reject_entities(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Extension(claims):     Extension<azile_auth::Claims>,
    Json(req):             Json<BulkEntityActionRequest>,
) -> Response {
    let identity_id = match Uuid::parse_str(&claims.sub) {
        Ok(id) => id,
        Err(_) => return err(StatusCode::UNAUTHORIZED, "invalid identity in token"),
    };

    if req.entity_ids.is_empty() {
        return err(StatusCode::BAD_REQUEST, "entity_ids must not be empty");
    }

    let notes = req.reviewer_notes.as_deref().unwrap_or("");

    let pending = match sqlx::query(
        "SELECT request_id, entity_id, entity_type_code, submitted_by
         FROM core_mdm.entity_approval_requests
         WHERE entity_id = ANY($1) AND tenant_id = $2 AND status = 'pending'",
    )
    .bind(&req.entity_ids)
    .bind(tenant_ctx.tenant_id)
    .fetch_all(&state.db)
    .await {
        Ok(rows) => rows,
        Err(e) => {
            tracing::error!(error=?e, "bulk_reject_entities fetch failed");
            return err(StatusCode::INTERNAL_SERVER_ERROR, "database error");
        }
    };

    let owned_types: Option<Vec<String>> = if claims.nxs_role.can_admin() {
        None
    } else {
        Some(
            sqlx::query_scalar::<_, String>(
                "SELECT entity_type_code FROM core_mdm.entity_type_assignments
                 WHERE tenant_id=$1 AND identity_id=$2 AND assignment_type='owner'",
            )
            .bind(tenant_ctx.tenant_id)
            .bind(identity_id)
            .fetch_all(&state.db)
            .await
            .unwrap_or_default(),
        )
    };

    let pending_ids: Vec<Uuid> = pending.iter().map(|r| r.get("entity_id")).collect();
    let mut succeeded = Vec::<String>::new();
    let mut skipped   = Vec::<String>::new();
    let mut failed    = Vec::<String>::new();

    for row in &pending {
        let request_id:   Uuid   = row.get("request_id");
        let entity_id:    Uuid   = row.get("entity_id");
        let type_code:    String = row.get("entity_type_code");
        let submitted_by: Uuid   = row.get("submitted_by");

        if let Some(ref owned) = owned_types {
            if !owned.contains(&type_code) {
                skipped.push(entity_id.to_string());
                continue;
            }
        }

        let mut txn = match state.db.begin().await {
            Ok(t)  => t,
            Err(e) => {
                tracing::error!(entity_id=%entity_id, error=?e, "bulk_reject: begin txn failed");
                failed.push(entity_id.to_string());
                continue;
            }
        };

        if sqlx::query(
            "UPDATE core_mdm.entity_approval_requests \
             SET status='rejected', reviewed_by=$1, reviewed_at=now(), reviewer_notes=$2 WHERE request_id=$3",
        )
        .bind(identity_id).bind(notes).bind(request_id)
        .execute(&mut *txn).await.is_err() {
            tracing::error!(entity_id=%entity_id, "bulk_reject: request update failed");
            failed.push(entity_id.to_string());
            continue;
        }

        if sqlx::query(
            "UPDATE core_mdm.entities \
             SET status='Draft', updated_at=now() WHERE entity_id=$1 AND tenant_id=$2",
        )
        .bind(entity_id).bind(tenant_ctx.tenant_id)
        .execute(&mut *txn).await.is_err() {
            tracing::error!(entity_id=%entity_id, "bulk_reject: entity draft reset failed");
            failed.push(entity_id.to_string());
            continue;
        }

        if let Err(e) = txn.commit().await {
            tracing::error!(entity_id=%entity_id, error=?e, "bulk_reject: commit failed");
            failed.push(entity_id.to_string());
            continue;
        }

        state.notification_service.notify(
            tenant_ctx.tenant_id, Some(submitted_by),
            "entity.rejected",
            &format!("{} record needs revision", type_code),
            &format!("Your {} record was returned for revision. Notes: {}", type_code, notes),
            "warning",
            json!({ "entity_id": entity_id, "entity_type": type_code, "notes": notes }),
        ).await.ok();

        state.audit_service.log_background(AuditEvent {
            tenant_id:     tenant_ctx.tenant_id,
            event_type:    "entity.rejected".to_string(),
            actor_id:      Some(identity_id),
            resource_type: "entity".to_string(),
            resource_id:   entity_id.to_string(),
            metadata:      json!({
                "entity_id": entity_id, "entity_type": type_code,
                "reviewer_notes": notes, "bulk": true,
            }),
            before:        None,
            after:         None,
        });

        succeeded.push(entity_id.to_string());
    }

    for &eid in &req.entity_ids {
        if !pending_ids.contains(&eid) {
            skipped.push(eid.to_string());
        }
    }

    tracing::info!(
        succeeded=%succeeded.len(), skipped=%skipped.len(), failed=%failed.len(),
        "bulk_reject_entities complete"
    );

    ok(json!({ "succeeded": succeeded, "skipped": skipped, "failed": failed }))
}
