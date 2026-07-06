use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};

use contracts::mdm::{
    distribution::CreateEntityRequest,
    matching::MatchRequest,
};

use crate::{
    proxy::mdm_proxy::proxy_mdm_post,
    state::AppState,
};

pub async fn create_entity(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(payload): Json<CreateEntityRequest>,
) -> impl IntoResponse {
    let payload_json = serde_json::to_value(payload).unwrap_or_default();

    match proxy_mdm_post(
        &state.services.http,
        &state.settings.mdm_core_url,
        "/entities",
        &headers,
        payload_json,
        &state.cb_mdm,
    )
    .await
    {
        Ok((status, body)) => (status, Json(body)).into_response(),
        Err(err) => {
            tracing::error!(error=%err, "proxy to mdm-core /entities failed");
            (
                StatusCode::BAD_GATEWAY,
                Json(serde_json::json!({
                    "success": false,
                    "error": "upstream service unavailable"
                })),
            )
                .into_response()
        }
    }
}

pub async fn execute_match(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(payload): Json<MatchRequest>,
) -> impl IntoResponse {
    let payload_json = serde_json::to_value(payload).unwrap_or_default();

    match proxy_mdm_post(
        &state.services.http,
        &state.settings.mdm_core_url,
        "/match",
        &headers,
        payload_json,
        &state.cb_mdm,
    )
    .await
    {
        Ok((status, body)) => (status, Json(body)).into_response(),
        Err(err) => {
            tracing::error!(error=%err, "proxy to mdm-core /match failed");
            (
                StatusCode::BAD_GATEWAY,
                Json(serde_json::json!({
                    "success": false,
                    "error": "upstream service unavailable"
                })),
            )
                .into_response()
        }
    }
}
