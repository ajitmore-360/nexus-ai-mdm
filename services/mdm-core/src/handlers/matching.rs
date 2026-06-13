use std::sync::Arc;

use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    Json,
};

use contracts::mdm::matching::{MatchRequest, MatchResponse};
use tracing::error;

use crate::handlers::ApiResponse;
use crate::AppState;

pub async fn execute_match(
    State(state): State<Arc<AppState>>,
    Json(request): Json<MatchRequest>,
) -> impl IntoResponse {
    match state.matching_service.execute_matching(request).await {
        Ok(response) => (
            StatusCode::OK,
            Json(ApiResponse {
                success: true,
                data: Some(response),
                error: None,
            }),
        ),
        Err(err) => {
            error!(error=?err, "match execution failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<MatchResponse> {
                    success: false,
                    data: None,
                    error: Some(err.to_string()),
                }),
            )
        }
    }
}
