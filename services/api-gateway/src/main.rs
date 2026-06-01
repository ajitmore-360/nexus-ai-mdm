mod config;
mod middleware;
mod proxy;
mod routes;
mod services;
mod state;
mod ws;

use axum::{
    middleware as axum_middleware,
    routing::{get, post},
    Router,
};

use std::net::SocketAddr;

use tower_http::cors::{
    Any,
    CorsLayer,
};

use config::settings::Settings;

use middleware::{
    auth::auth_middleware,
    tenant::tenant_middleware,
};

use routes::{
    ai::copilot,
    health::health,
};

use services::ServiceClients;
use state::AppState;

//
// =========================================
// 🚀 MAIN
// =========================================
//

#[tokio::main]
async fn main() {

    // =====================================
    // ENV
    // =====================================
    dotenvy::dotenv().ok();

    // =====================================
    // CONFIG
    // =====================================
    let settings = Settings::from_env();

    println!("✅ Configuration loaded");

    // =====================================
    // SERVICE CLIENTS
    // =====================================
    let services = ServiceClients::new();

    println!("✅ Service clients initialized");

    // =====================================
    // APP STATE
    // =====================================
    let state = AppState {
        settings: settings.clone(),
        services,
    };

    // =====================================
    // CORS
    // =====================================
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    // =====================================
    // PROTECTED ROUTES
    // =====================================
    let protected_routes = Router::new()

        // =================================
        // AI COPILOT
        // =================================
        .route("/copilot", post(copilot))

        // =================================
        // FUTURE ROUTES
        // =================================
        // .route("/search", post(search))
        // .route("/merge", post(merge))
        // .route("/survivorship", post(survivorship))

        // =================================
        // MIDDLEWARE ORDER
        // auth -> tenant -> handlers
        // =================================
        .layer(axum_middleware::from_fn_with_state(
            state.clone(),
            auth_middleware,
        ))
        .layer(axum_middleware::from_fn_with_state(
            state.clone(),
            tenant_middleware,
        ));

    // =====================================
    // APPLICATION ROUTER
    // =====================================
    let app = Router::new()

        // =================================
        // PUBLIC ROUTES
        // =================================
        .route("/health", get(health))

        // =================================
        // PROTECTED ROUTES
        // =================================
        .nest("/", protected_routes)

        // =================================
        // STATE
        // =================================
        .with_state(state.clone())

        // =================================
        // CORS
        // =================================
        .layer(cors);

    // =====================================
    // WS SERVER
    // =====================================
    tokio::spawn(async move {

        if let Err(err) = ws::start_ws_server().await {
            eprintln!("❌ WS server failed: {:?}", err);
        }

    });

    println!("✅ WebSocket server started");

    // =====================================
    // BIND ADDRESS
    // =====================================
    let addr = SocketAddr::from((
        [127, 0, 0, 1],
        settings.gateway_port,
    ));

    println!("🚀 API Gateway running on http://{}", addr);

    // =====================================
    // START SERVER
    // =====================================
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("❌ Failed to bind API Gateway");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .expect("❌ API Gateway crashed");
}

//
// =========================================
// 🛑 SHUTDOWN
// =========================================
//

async fn shutdown_signal() {

    use tokio::signal;

    let ctrl_c = async {

        signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {

        signal::unix::signal(
            signal::unix::SignalKind::terminate()
        )
        .expect("failed to install signal handler")
        .recv()
        .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }

    println!("🛑 Shutdown signal received");
}