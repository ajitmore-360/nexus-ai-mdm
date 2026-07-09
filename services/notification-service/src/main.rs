mod config;
mod delivery;
mod hub;
mod subscriber;

use std::{net::SocketAddr, sync::Arc};

use axum::{
    extract::{
        ws::WebSocketUpgrade,
        Path, Query, State,
    },
    http::{HeaderName, HeaderValue, Method, StatusCode, header::{AUTHORIZATION, CONTENT_TYPE}},
    response::IntoResponse,
    routing::{delete, get, post},
    Json, Router,
};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use uuid::Uuid;

use config::NotificationSettings;
use hub::{ConnectionHub, PushNotification};
use subscriber::RedisListener;

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// APP STATE
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

#[derive(Clone)]
struct AppState {
    hub:  Arc<ConnectionHub>,
    pool: PgPool,
    http: Arc<Client>,
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// HANDLERS
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// GET /health
async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "status": "healthy", "service": "notification-service" }))
}

async fn metrics_handler() -> String {
    azile_telemetry::metrics::render_metrics()
        .unwrap_or_else(|e| format!("# metrics error: {}", e))
}

/// GET /ws?tenant_id=<uuid>&user_id=<uuid>
///
/// Upgrades the connection to WebSocket.  The client receives all notifications
/// published to the tenant's Redis pub/sub channel.
#[derive(Deserialize)]
struct WsParams {
    tenant_id: Uuid,
    user_id:   Option<Uuid>,
}

async fn ws_handler(
    ws:              WebSocketUpgrade,
    Query(params):   Query<WsParams>,
    State(state):    State<AppState>,
) -> axum::response::Response {
    let hub       = Arc::clone(&state.hub);
    let tenant_id = params.tenant_id;
    let user_id   = params.user_id;

    ws.on_upgrade(move |socket| async move {
        hub.handle_connection(socket, tenant_id, user_id).await;
    })
}

/// POST /notify  â€” internal endpoint for other services to push a notification.
/// Broadcasts to in-app WebSocket subscribers and dispatches webhook delivery.
async fn push(
    State(state): State<AppState>,
    Json(notif):  Json<PushNotification>,
) -> Json<serde_json::Value> {
    // 1. In-app WebSocket delivery (fire-and-forget, always first)
    state.hub.broadcast(&notif).await;

    // 2. Webhook delivery â€” spawned so it doesn't block the response
    let pool = state.pool.clone();
    let http = Arc::clone(&state.http);
    let notif_clone = notif.clone();
    tokio::spawn(async move {
        if let Err(e) = delivery::webhook::dispatch(&pool, &http, &notif_clone).await {
            tracing::warn!(error=%e, "webhook dispatch error");
        }
    });

    Json(serde_json::json!({ "success": true }))
}

// â”€â”€ Webhook subscription management â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

#[derive(Debug, Deserialize)]
struct CreateWebhookRequest {
    tenant_id:   Uuid,
    url:         String,
    event_types: Option<Vec<String>>,
    secret:      Option<String>,
}

#[derive(Debug, Serialize)]
#[allow(dead_code)]
struct WebhookSubscription {
    subscription_id: Uuid,
    tenant_id:       Uuid,
    url:             String,
    event_types:     Vec<String>,
    enabled:         bool,
}

async fn list_webhooks(
    State(state):  State<AppState>,
    Query(params): Query<std::collections::HashMap<String, String>>,
) -> impl IntoResponse {
    use sqlx::Row;
    let tenant_id = match params.get("tenant_id").and_then(|s| s.parse::<Uuid>().ok()) {
        Some(id) => id,
        None => return (StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "success": false, "error": "tenant_id required" }))).into_response(),
    };
    let rows = sqlx::query(
        "SELECT subscription_id, tenant_id, url, event_types, enabled FROM notifications.webhook_subscriptions WHERE tenant_id = $1"
    )
    .bind(tenant_id)
    .fetch_all(&state.pool)
    .await;

    match rows {
        Ok(rows) => {
            let items: Vec<_> = rows.iter().map(|r| serde_json::json!({
                "subscription_id": r.get::<Uuid,_>("subscription_id"),
                "tenant_id":       r.get::<Uuid,_>("tenant_id"),
                "url":             r.get::<String,_>("url"),
                "event_types":     r.get::<Vec<String>,_>("event_types"),
                "enabled":         r.get::<bool,_>("enabled"),
            })).collect();
            (StatusCode::OK, Json(serde_json::json!({ "success": true, "items": items }))).into_response()
        }
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

async fn create_webhook(
    State(state): State<AppState>,
    Json(req):    Json<CreateWebhookRequest>,
) -> impl IntoResponse {
    let event_types = req.event_types.unwrap_or_default();
    let result = sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO notifications.webhook_subscriptions (tenant_id, url, event_types, secret)
        VALUES ($1, $2, $3, $4)
        RETURNING subscription_id
        "#,
    )
    .bind(req.tenant_id)
    .bind(&req.url)
    .bind(&event_types)
    .bind(req.secret.as_deref())
    .fetch_one(&state.pool)
    .await;

    match result {
        Ok(id) => (StatusCode::CREATED,
            Json(serde_json::json!({ "success": true, "subscription_id": id }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// â”€â”€ Transactional email â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

#[derive(Debug, Deserialize)]
struct SendInviteEmailRequest {
    to:             String,
    display_name:   Option<String>,
    activation_url: String,
    invited_by:     Option<String>,
}

/// POST /internal/emails/invite
/// Internal endpoint â€” called by mdm-core after creating an invite token.
async fn handle_send_invite_email(
    Json(req): Json<SendInviteEmailRequest>,
) -> impl IntoResponse {
    let name = req.display_name.as_deref().unwrap_or(&req.to);
    match delivery::email::send_invite_email(
        &req.to,
        name,
        &req.activation_url,
        req.invited_by.as_deref(),
    )
    .await
    {
        Ok(_) => (
            StatusCode::OK,
            Json(serde_json::json!({ "success": true })),
        )
            .into_response(),
        Err(e) => {
            tracing::warn!(error=%e, to=%req.to, "invite email dispatch failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "success": false, "error": e.to_string() })),
            )
                .into_response()
        }
    }
}

#[derive(Debug, Deserialize)]
struct SendResetEmailRequest {
    to:        String,
    name:      Option<String>,
    reset_url: String,
}

/// POST /internal/emails/reset-password
/// Internal endpoint â€” called by mdm-core after creating a password reset token.
async fn handle_send_reset_email(
    Json(req): Json<SendResetEmailRequest>,
) -> impl IntoResponse {
    let name = req.name.as_deref().unwrap_or(&req.to);
    match delivery::email::send_password_reset_email(&req.to, name, &req.reset_url).await {
        Ok(_) => (StatusCode::OK, Json(serde_json::json!({ "success": true }))).into_response(),
        Err(e) => {
            tracing::warn!(error=%e, to=%req.to, "reset email dispatch failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "success": false, "error": e.to_string() })),
            )
                .into_response()
        }
    }
}

async fn delete_webhook(
    State(state):        State<AppState>,
    Path(id):            Path<Uuid>,
    Query(params):       Query<std::collections::HashMap<String, String>>,
) -> impl IntoResponse {
    let tenant_id = match params.get("tenant_id").and_then(|s| s.parse::<Uuid>().ok()) {
        Some(id) => id,
        None => return (StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "success": false, "error": "tenant_id required" }))).into_response(),
    };
    let result = sqlx::query(
        "DELETE FROM notifications.webhook_subscriptions WHERE subscription_id = $1 AND tenant_id = $2"
    )
    .bind(id)
    .bind(tenant_id)
    .execute(&state.pool)
    .await;

    match result {
        Ok(r) if r.rows_affected() > 0 =>
            (StatusCode::OK, Json(serde_json::json!({ "success": true }))).into_response(),
        Ok(_) =>
            (StatusCode::NOT_FOUND, Json(serde_json::json!({ "success": false, "error": "not found" }))).into_response(),
        Err(e) =>
            (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// MAIN
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    azile_telemetry::tracing_init::init_tracing("notification-service");
    azile_telemetry::metrics::init_metrics("notification-service");

    let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());
    tracing::info!(app_env = %app_env, "Notification Service environment loaded");

    let settings = NotificationSettings::from_env().unwrap_or_else(|e| {
        eprintln!("[FATAL] Configuration error: {e}");
        std::process::exit(1);
    });
    tracing::info!("Notification Service starting on port {}", settings.port);

    // Emit a prominent warning so ops teams know email delivery is disabled.
    if settings.smtp_host.is_empty() {
        tracing::warn!(
            "SMTP_HOST is not set â€” transactional emails (invites, password resets) \
             will be logged but NOT delivered. Set SMTP_HOST in the environment to \
             enable real email delivery."
        );
    } else {
        tracing::info!(smtp_host = %settings.smtp_host, "SMTP configured â€” email delivery enabled");
    }

    let allowed_origins_raw = std::env::var("ALLOWED_ORIGINS")
        .unwrap_or_else(|_| "http://localhost:3000,http://localhost:4000".to_string());
    if matches!(app_env.as_str(), "production" | "prod" | "staging" | "stage") {
        if allowed_origins_raw.contains("localhost") {
            panic!(
                "SECURITY: ALLOWED_ORIGINS contains 'localhost' in APP_ENV={}. Set to your production domain.",
                app_env
            );
        }
    }

    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(5)
        .connect(&settings.database_url)
        .await
        .expect("failed to connect to PostgreSQL");

    let hub       = Arc::new(ConnectionHub::new());
    let hub_clone = Arc::clone(&hub);
    let http      = Arc::new(
        Client::builder()
            .timeout(std::time::Duration::from_secs(10))
            .build()
            .expect("failed to build HTTP client"),
    );

    // Start Redis pub/sub listener in background
    let redis_url = settings.redis_url.clone();
    tokio::spawn(async move {
        let listener = RedisListener::new(redis_url, hub_clone);
        if let Err(e) = listener.run().await {
            tracing::error!(error=%e, "Redis listener exited with error");
        }
    });

    let state = AppState { hub, pool, http };

    let allowed_origins: Vec<HeaderValue> = allowed_origins_raw
        .split(',')
        .filter_map(|s| s.trim().parse().ok())
        .collect();

    let cors = CorsLayer::new()
        .allow_origin(allowed_origins)
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers([CONTENT_TYPE, AUTHORIZATION, HeaderName::from_static("x-tenant-id"), HeaderName::from_static("x-request-id")])
        .allow_credentials(true);

    let app = Router::new()
        .route("/health",              get(health))
        .route("/metrics",             get(metrics_handler))
        .route("/ws",                  get(ws_handler))
        .route("/notify",              post(push))
        // Webhook subscription management
        .route("/webhooks",            get(list_webhooks).post(create_webhook))
        .route("/webhooks/:id",        delete(delete_webhook))
        // Internal transactional emails (not exposed via api-gateway)
        .route("/internal/emails/invite",          post(handle_send_invite_email))
        .route("/internal/emails/reset-password",  post(handle_send_reset_email))
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], settings.port));
    tracing::info!("Notification Service listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("failed to bind notification service");

    axum::serve(listener, app)
        .await
        .expect("notification service crashed");
}
