use axum::{
    extract::State,
    http::{Request, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
};

use sqlx::PgPool;
use uuid::Uuid;

pub async fn tenant_context_middleware<B>(
    State(pool): State<PgPool>,
    mut request: Request<B>,
    next: Next<B>,
) -> Response {

    let tenant_id = request
        .headers()
        .get("x-tenant-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| Uuid::parse_str(v).ok());

    let tenant_id = match tenant_id {
        Some(v) => v,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                "Missing or invalid x-tenant-id header",
            )
                .into_response();
        }
    };

    //
    // IMPORTANT:
    // SET LOCAL tenant variable
    //

    if let Ok(mut conn) = pool.acquire().await {

        let _ = sqlx::query(
            r#"
            SELECT set_config(
                'app.current_tenant',
                $1,
                true
            )
            "#
        )
        .bind(tenant_id.to_string())
        .execute(&mut *conn)
        .await;
    }

    request.extensions_mut().insert(tenant_id);

    next.run(request).await
}