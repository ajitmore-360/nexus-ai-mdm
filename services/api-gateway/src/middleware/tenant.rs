use axum::{
    extract::Request,
    http::StatusCode,
    middleware::Next,
    response::Response,
};

use uuid::Uuid;

#[derive(Clone, Debug)]
pub struct TenantContext {
    pub tenant_id: Uuid,
}

pub async fn tenant_middleware(
    mut request: Request,
    next: Next,
) -> Result<Response, StatusCode> {

    //
    // ========================================
    // TENANT HEADER
    // ========================================
    //

    let tenant_header =
        request
            .headers()
            .get("x-tenant-id")
            .ok_or(StatusCode::BAD_REQUEST)?;

    let tenant_str =
        tenant_header
            .to_str()
            .map_err(|_| StatusCode::BAD_REQUEST)?;

    let tenant_id =
        Uuid::parse_str(tenant_str)
            .map_err(|_| StatusCode::BAD_REQUEST)?;

    //
    // ========================================
    // STORE IN REQUEST EXTENSIONS
    // ========================================
    //

    request.extensions_mut().insert(
        TenantContext {
            tenant_id,
        }
    );

    Ok(
        next.run(request).await
    )
}