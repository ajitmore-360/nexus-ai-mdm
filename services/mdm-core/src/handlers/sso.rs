// ============================================================================
// SSO Handlers — SAML 2.0 SP endpoints + SSO config CRUD + SCIM token mgmt
//
// Public SAML endpoints (no JWT auth, for browser redirect flow):
//   GET  /saml/:tenant_id/metadata   â†’ SP XML metadata
//   GET  /saml/:tenant_id/init       â†’ initiate SSO (redirect to IdP)
//   POST /saml/:tenant_id/acs        â†’ assertion consumer (issues JWT)
//
// Protected admin endpoints (standard JWT auth + admin role):
//   GET/PUT /sso-configurations
//   DELETE  /sso-configurations/:type
//   GET/POST /scim/tokens
//   DELETE   /scim/tokens/:id
// ============================================================================

use axum::{
    body::Body,
    extract::{Form, Path, Query, State},
    http::{header, Response, StatusCode},
    response::IntoResponse,
    Json,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use uuid::Uuid;

use azile_auth::{issue_tokens, Claims, JwtConfig, Role};

use crate::{
    handlers::ApiResponse,
    services::sso_service::UpsertSsoConfig,
    AppState,
};

// â"€â"€ SP Metadata â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn saml_metadata(
    Path(tenant_id_str): Path<String>,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let tenant_id = match Uuid::parse_str(&tenant_id_str) {
        Ok(id) => id,
        Err(_) => return (StatusCode::BAD_REQUEST, "Invalid tenant ID").into_response(),
    };

    let cfg = match state.sso_service.get_config(tenant_id).await {
        Ok(Some(c)) => c,
        Ok(None) => return (StatusCode::NOT_FOUND, "SSO not configured").into_response(),
        Err(e) => {
            tracing::error!(error=%e, "metadata fetch error");
            return (StatusCode::INTERNAL_SERVER_ERROR, "Internal error").into_response();
        }
    };

    let base_url = std::env::var("BASE_URL")
        .unwrap_or_else(|_| "http://localhost:8081".to_string());
    let xml = state.sso_service.generate_metadata(&cfg, &base_url);

    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "application/xml; charset=utf-8")
        .body(Body::from(xml))
        .unwrap()
}

// â"€â"€ SAML Initiate â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

#[derive(Deserialize)]
pub struct SamlInitQuery {
    pub redirect: Option<String>,
}

pub async fn saml_init(
    Path(tenant_id_str): Path<String>,
    Query(q): Query<SamlInitQuery>,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    let tenant_id = match Uuid::parse_str(&tenant_id_str) {
        Ok(id) => id,
        Err(_) => return (StatusCode::BAD_REQUEST, "Invalid tenant ID").into_response(),
    };

    let cfg = match state.sso_service.get_config(tenant_id).await {
        Ok(Some(c)) if c.is_enabled => c,
        Ok(Some(_)) => return (StatusCode::FORBIDDEN, "SSO is disabled for this tenant").into_response(),
        Ok(None) => return (StatusCode::NOT_FOUND, "SSO not configured").into_response(),
        Err(e) => {
            tracing::error!(error=%e, "SAML init error");
            return (StatusCode::INTERNAL_SERVER_ERROR, "Internal error").into_response();
        }
    };

    let relay_state = Uuid::new_v4().to_string();
    let redirect_url = q.redirect.unwrap_or_else(|| "/dashboard".to_string());
    let base_url = std::env::var("BASE_URL")
        .unwrap_or_else(|_| "http://localhost:8081".to_string());

    match state
        .sso_service
        .build_authn_redirect(&cfg, &base_url, &relay_state, &redirect_url, tenant_id)
        .await
    {
        Ok(redirect) => Response::builder()
            .status(StatusCode::FOUND)
            .header(header::LOCATION, redirect)
            .body(Body::empty())
            .unwrap(),
        Err(e) => {
            tracing::error!(error=%e, "SAML redirect build failed");
            (StatusCode::INTERNAL_SERVER_ERROR, "Failed to build SSO redirect").into_response()
        }
    }
}

// â"€â"€ SAML ACS — assertion consumer service â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

#[derive(Deserialize)]
pub struct AcsForm {
    #[serde(rename = "SAMLResponse")]
    pub saml_response: String,
    #[serde(rename = "RelayState")]
    pub relay_state: Option<String>,
}

#[derive(Serialize)]
pub struct SsoTokenResponse {
    pub access_token:   String,
    pub refresh_token:  String,
    pub token_type:     String,
    pub expires_in:     u64,
    pub redirect_url:   String,
    pub email:          String,
    pub display_name:   Option<String>,
    pub tenant_id:      Uuid,
}

pub async fn saml_acs(
    Path(tenant_id_str): Path<String>,
    State(state): State<Arc<AppState>>,
    Form(form): Form<AcsForm>,
) -> impl IntoResponse {
    let tenant_id = match Uuid::parse_str(&tenant_id_str) {
        Ok(id) => id,
        Err(_) => return (StatusCode::BAD_REQUEST, Json(serde_json::json!({"error":"Invalid tenant ID"}))).into_response(),
    };

    let cfg = match state.sso_service.get_config(tenant_id).await {
        Ok(Some(c)) if c.is_enabled => c,
        Ok(Some(_)) => return (StatusCode::FORBIDDEN, Json(serde_json::json!({"error":"SSO disabled"}))).into_response(),
        Ok(None) => return (StatusCode::NOT_FOUND, Json(serde_json::json!({"error":"SSO not configured"}))).into_response(),
        Err(e) => {
            tracing::error!(error=%e, "ACS config fetch error");
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"error":"Internal error"}))).into_response();
        }
    };

    let relay_state = form.relay_state.as_deref().unwrap_or("");

    let (claims_saml, redirect_url) = match state
        .sso_service
        .process_acs_response(&form.saml_response, relay_state, &cfg)
        .await
    {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!(error=%e, "SAML ACS failed");
            return (StatusCode::UNAUTHORIZED, Json(serde_json::json!({"error": e.to_string()}))).into_response();
        }
    };

    // JIT provisioning: ensure identity + tenant membership exist
    let (identity_id, role_str) =
        match provision_user(&state, tenant_id, &claims_saml, &cfg).await {
            Ok(r) => r,
            Err(e) => {
                tracing::error!(error=%e, "JIT provisioning failed");
                return (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"error":"Provisioning failed"}))).into_response();
            }
        };

    // Issue JWT using the standard auth mechanism
    let parsed_role: Role = role_str.parse().unwrap_or(Role::Steward);
    let jwt_cfg = match JwtConfig::from_env() {
        Ok(c) => c,
        Err(e) => {
            tracing::error!(error=%e, "JwtConfig load failed");
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"error":"Token config error"}))).into_response();
        }
    };

    let token_pair = match issue_tokens(&jwt_cfg, identity_id, tenant_id, &claims_saml.email, parsed_role) {
        Ok(p) => p,
        Err(e) => {
            tracing::error!(error=%e, "JWT issue failed");
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"error":"Token issue failed"}))).into_response();
        }
    };

    tracing::info!(email=%claims_saml.email, tenant_id=%tenant_id, "SAML SSO login successful");

    (
        StatusCode::OK,
        Json(SsoTokenResponse {
            access_token:   token_pair.access_token,
            refresh_token:  token_pair.refresh_token,
            token_type:     token_pair.token_type,
            expires_in:     token_pair.expires_in,
            redirect_url,
            email: claims_saml.email.clone(),
            display_name: claims_saml.display_name.clone(),
            tenant_id,
        }),
    )
        .into_response()
}

// â"€â"€ JIT Provisioning â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

async fn provision_user(
    state: &Arc<AppState>,
    tenant_id: Uuid,
    claims: &crate::services::sso_service::SamlClaims,
    cfg: &crate::services::sso_service::SsoConfig,
) -> anyhow::Result<(Uuid, String)> {
    // Determine role from group â†’ role mapping
    let group_role_map = cfg
        .group_role_mappings
        .as_object()
        .cloned()
        .unwrap_or_default();
    let mut assigned_role = cfg.default_role.clone();
    for group in &claims.groups {
        if let Some(role) = group_role_map.get(group).and_then(|v| v.as_str()) {
            assigned_role = role.to_string();
            break;
        }
    }

    if !cfg.auto_provision {
        let existing: Option<Uuid> = sqlx::query_scalar(
            r#"
            SELECT i.identity_id
            FROM core_mdm.identities i
            JOIN core_mdm.tenant_memberships tm ON tm.identity_id = i.identity_id
            WHERE i.email = $1 AND tm.tenant_id = $2
            "#,
        )
        .bind(&claims.email)
        .bind(tenant_id)
        .fetch_optional(&state.db)
        .await?;
        let id = existing.ok_or_else(|| {
            anyhow::anyhow!("auto_provision is off and user is not in the tenant")
        })?;
        return Ok((id, assigned_role));
    }

    let identity_id: Uuid = sqlx::query_scalar(
        r#"
        INSERT INTO core_mdm.identities (email, display_name, is_active, auth_provider)
        VALUES ($1, COALESCE($2, ''), true, 'saml')
        ON CONFLICT (email) DO UPDATE SET
            display_name = COALESCE(NULLIF($2, ''), identities.display_name),
            is_active    = true,
            updated_at   = NOW()
        RETURNING identity_id
        "#,
    )
    .bind(&claims.email)
    .bind(claims.display_name.as_deref().unwrap_or(""))
    .fetch_one(&state.db)
    .await?;

    sqlx::query(
        r#"
        INSERT INTO core_mdm.tenant_memberships (tenant_id, identity_id, role)
        VALUES ($1, $2, $3)
        ON CONFLICT (tenant_id, identity_id) DO UPDATE SET role = $3
        "#,
    )
    .bind(tenant_id)
    .bind(identity_id)
    .bind(&assigned_role)
    .execute(&state.db)
    .await?;

    Ok((identity_id, assigned_role))
}

// â"€â"€ SSO Config CRUD â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn get_sso_config(
    State(state): State<Arc<AppState>>,
    axum::extract::Extension(claims): axum::extract::Extension<Claims>,
) -> impl IntoResponse {
    match state.sso_service.get_config(claims.nxs_tenant_id).await {
        Ok(Some(cfg)) => (StatusCode::OK, Json(ApiResponse { success: true, data: Some(cfg), error: None })).into_response(),
        Ok(None) => (StatusCode::OK, Json(ApiResponse::<()> { success: true, data: None, error: None })).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse::<()> { success: false, data: None, error: Some(e.to_string()) })).into_response(),
    }
}

pub async fn upsert_sso_config(
    State(state): State<Arc<AppState>>,
    axum::extract::Extension(claims): axum::extract::Extension<Claims>,
    Json(payload): Json<UpsertSsoConfig>,
) -> impl IntoResponse {
    if !claims.nxs_role.can_admin() {
        return (StatusCode::FORBIDDEN, Json(ApiResponse::<()> { success: false, data: None, error: Some("Admin required".into()) })).into_response();
    }
    let created_by = claims.user_id().unwrap_or(Uuid::nil());
    match state.sso_service.upsert_config(claims.nxs_tenant_id, created_by, payload).await {
        Ok(cfg) => (StatusCode::OK, Json(ApiResponse { success: true, data: Some(cfg), error: None })).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse::<()> { success: false, data: None, error: Some(e.to_string()) })).into_response(),
    }
}

pub async fn delete_sso_config(
    Path(provider_type): Path<String>,
    State(state): State<Arc<AppState>>,
    axum::extract::Extension(claims): axum::extract::Extension<Claims>,
) -> impl IntoResponse {
    if !claims.nxs_role.can_admin() {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.sso_service.delete_config(claims.nxs_tenant_id, &provider_type).await {
        Ok(()) => StatusCode::NO_CONTENT.into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

// â"€â"€ SCIM Token Management â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

#[derive(Deserialize)]
pub struct CreateScimTokenPayload {
    pub description: String,
    pub expires_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Serialize)]
pub struct CreatedScimToken {
    pub token:     crate::services::sso_service::ScimToken,
    pub raw_token: String,
}

pub async fn list_scim_tokens(
    State(state): State<Arc<AppState>>,
    axum::extract::Extension(claims): axum::extract::Extension<Claims>,
) -> impl IntoResponse {
    if !claims.nxs_role.can_admin() {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.sso_service.list_scim_tokens(claims.nxs_tenant_id).await {
        Ok(tokens) => (StatusCode::OK, Json(ApiResponse { success: true, data: Some(tokens), error: None })).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse::<()> { success: false, data: None, error: Some(e.to_string()) })).into_response(),
    }
}

pub async fn create_scim_token(
    State(state): State<Arc<AppState>>,
    axum::extract::Extension(claims): axum::extract::Extension<Claims>,
    Json(payload): Json<CreateScimTokenPayload>,
) -> impl IntoResponse {
    if !claims.nxs_role.can_admin() {
        return StatusCode::FORBIDDEN.into_response();
    }
    let created_by = claims.user_id().unwrap_or(Uuid::nil());
    match state
        .sso_service
        .create_scim_token(claims.nxs_tenant_id, created_by, &payload.description, payload.expires_at)
        .await
    {
        Ok((token, raw)) => (
            StatusCode::CREATED,
            Json(ApiResponse { success: true, data: Some(CreatedScimToken { token, raw_token: raw }), error: None }),
        ).into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()> { success: false, data: None, error: Some(e.to_string()) }),
        ).into_response(),
    }
}

pub async fn revoke_scim_token(
    Path(token_id): Path<Uuid>,
    State(state): State<Arc<AppState>>,
    axum::extract::Extension(claims): axum::extract::Extension<Claims>,
) -> impl IntoResponse {
    if !claims.nxs_role.can_admin() {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.sso_service.revoke_scim_token(token_id, claims.nxs_tenant_id).await {
        Ok(()) => StatusCode::NO_CONTENT.into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}
