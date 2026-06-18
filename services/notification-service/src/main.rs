mod config;
mod hub;
mod subscriber;

use std::{net::SocketAddr, sync::Arc};

use axum::{
    extract::{
        ws::WebSocketUpgrade,
        Query, State,
    },
    http::{HeaderName, HeaderValue, Method, header::{AUTHORIZATION, CONTENT_TYPE}},
    routing::get,
    Json, Router,
};
use serde::Deserialize;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use uuid::Uuid;

use config::NotificationSettings;
use hub::{ConnectionHub, PushNotification};
use subscriber::RedisListener;

// ─────────────────────────────────────────────────────────────────────────────
// APP STATE
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Clone)]
struct AppState {
    hub: Arc<ConnectionHub>,
}

// ─────────────────────────────────────────────────────────────────────────────
// HANDLERS
// ─────────────────────────────────────────────────────────────────────────────

/// GET /health
async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "status": "healthy", "service": "notification-service" }))
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

/// POST /notify  — internal endpoint for other services to push a notification
async fn push(
    State(state): State<AppState>,
    Json(notif):  Json<PushNotification>,
) -> Json<serde_json::Value> {
    state.hub.broadcast(&notif).await;
    Json(serde_json::json!({ "success": true }))
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────────────────────────────────────

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("notification_service=info".parse().unwrap()),
        )
        .init();

    let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());
    tracing::info!(app_env = %app_env, "Notification Service environment loaded");

    let settings = NotificationSettings::from_env();
    tracing::info!("Notification Service starting on port {}", settings.port);

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

    let hub       = Arc::new(ConnectionHub::new());
    let hub_clone = Arc::clone(&hub);

    // Start Redis pub/sub listener in background
    let redis_url = settings.redis_url.clone();
    tokio::spawn(async move {
        let listener = RedisListener::new(redis_url, hub_clone);
        if let Err(e) = listener.run().await {
            tracing::error!(error=%e, "Redis listener exited with error");
        }
    });

    let state = AppState { hub };

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
        .route("/health", get(health))
        .route("/ws",     get(ws_handler))
        .route("/notify", axum::routing::post(push))
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
