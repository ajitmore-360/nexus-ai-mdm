use axum::{
    http::StatusCode,
    response::IntoResponse,
    Json,
};

use serde::{Deserialize, Serialize};

use crate::survivorship::engine::apply_survivorship;

use contracts::mdm::{
    entity::CanonicalEntity,
    golden_record::GoldenRecord,
    survivorship::SurvivorshipRule,
};

//
// ========================================
// REQUEST MODELS
// ========================================
//

#[derive(Debug, Deserialize)]
pub struct MergeRequest {
    pub entities: Vec<CanonicalEntity>,

    pub rules: Vec<SurvivorshipRule>,
}

#[derive(Debug, Deserialize)]
pub struct SearchRequest {
    pub query: String,
}

//
// ========================================
// API RESPONSE
// ========================================
//

#[derive(Debug, Serialize)]
pub struct ApiResponse<T>
where
    T: Serialize,
{
    pub success: bool,

    pub data: Option<T>,

    pub error: Option<String>,
}

//
// ========================================
// MERGE HANDLER
// ========================================
//

pub async fn merge(
    Json(payload): Json<MergeRequest>,
) -> impl IntoResponse {

    // =========================
    // VALIDATION
    // =========================

    if payload.entities.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<GoldenRecord> {
                success: false,
                data: None,
                error: Some(
                    "entities cannot be empty".to_string()
                ),
            }),
        );
    }

    if payload.rules.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<GoldenRecord> {
                success: false,
                data: None,
                error: Some(
                    "rules cannot be empty".to_string()
                ),
            }),
        );
    }

    // =========================
    // EXECUTE SURVIVORSHIP
    // =========================

    let result = apply_survivorship(
        payload.entities,
        payload.rules,
    );

    // =========================
    // SUCCESS RESPONSE
    // =========================

    (
        StatusCode::OK,
        Json(ApiResponse {
            success: true,
            data: Some(result),
            error: None,
        }),
    )
}

//
// ========================================
// SEARCH HANDLER
// ========================================
//

pub async fn search(
    Json(payload): Json<SearchRequest>,
) -> impl IntoResponse {

    (
        StatusCode::OK,
        Json(ApiResponse {
            success: true,
            data: Some(payload.query),
            error: None,
        }),
    )
}