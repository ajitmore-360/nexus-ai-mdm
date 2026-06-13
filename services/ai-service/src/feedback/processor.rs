use anyhow::Result;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row};
use tracing::{info, instrument};
use uuid::Uuid;

/// A steward override event — the human corrected a system decision.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StewardFeedback {
    pub tenant_id:        Uuid,
    pub steward_id:       Uuid,
    pub feedback_type:    FeedbackType,
    pub source_entity_id: Uuid,
    pub candidate_id:     Option<Uuid>,
    pub feature_vector:   serde_json::Value,
    pub system_decision:  String,
    pub human_decision:   String,
    pub notes:            Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FeedbackType {
    MatchApproved,
    MatchRejected,
    MergeOverridden,
    SurvivorshipOverridden,
}

impl std::fmt::Display for FeedbackType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            FeedbackType::MatchApproved          => "match_approved",
            FeedbackType::MatchRejected          => "match_rejected",
            FeedbackType::MergeOverridden        => "merge_overridden",
            FeedbackType::SurvivorshipOverridden => "survivorship_overridden",
        };
        write!(f, "{}", s)
    }
}

#[allow(dead_code)]
#[derive(Debug, Serialize)]
pub struct FeedbackSummary {
    pub approved:   i64,
    pub rejected:   i64,
    pub overridden: i64,
    pub total:      i64,
}

/// Persists steward feedback and provides basic analysis for adaptive scoring.
pub struct FeedbackProcessor {
    pool: PgPool,
}

impl FeedbackProcessor {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Record a steward feedback event.
    #[instrument(skip(self, feedback), fields(tenant_id=%feedback.tenant_id))]
    pub async fn record(&self, feedback: &StewardFeedback) -> Result<Uuid> {
        let feedback_id = Uuid::new_v4();

        sqlx::query(
            r#"
            INSERT INTO ai.steward_feedback (
                feedback_id, tenant_id, steward_id, feedback_type,
                source_entity_id, candidate_id, feature_vector,
                system_decision, human_decision, notes, created_at
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
            "#,
        )
        .bind(feedback_id)
        .bind(feedback.tenant_id)
        .bind(feedback.steward_id)
        .bind(feedback.feedback_type.to_string())
        .bind(feedback.source_entity_id)
        .bind(feedback.candidate_id)
        .bind(&feedback.feature_vector)
        .bind(&feedback.system_decision)
        .bind(&feedback.human_decision)
        .bind(feedback.notes.as_deref())
        .bind(Utc::now())
        .execute(&self.pool)
        .await?;

        info!(
            feedback_id=%feedback_id,
            feedback_type=%feedback.feedback_type,
            "steward feedback recorded"
        );

        Ok(feedback_id)
    }

    /// Count feedback events by type for a tenant (last N days).
    #[allow(dead_code)]
    pub async fn summary(&self, tenant_id: Uuid, days: i32) -> Result<FeedbackSummary> {
        let row = sqlx::query(
            r#"
            SELECT
                COUNT(*) FILTER (WHERE feedback_type = 'match_approved')    AS approved,
                COUNT(*) FILTER (WHERE feedback_type = 'match_rejected')    AS rejected,
                COUNT(*) FILTER (WHERE feedback_type = 'merge_overridden')  AS overridden,
                COUNT(*)                                                     AS total
            FROM ai.steward_feedback
            WHERE tenant_id = $1
              AND created_at >= NOW() - ($2 * INTERVAL '1 day')
            "#,
        )
        .bind(tenant_id)
        .bind(days)
        .fetch_one(&self.pool)
        .await?;

        Ok(FeedbackSummary {
            approved:   row.try_get::<i64, _>("approved").unwrap_or(0),
            rejected:   row.try_get::<i64, _>("rejected").unwrap_or(0),
            overridden: row.try_get::<i64, _>("overridden").unwrap_or(0),
            total:      row.try_get::<i64, _>("total").unwrap_or(0),
        })
    }

    /// Fetch feature vectors for approved matches (for weight tuning analysis).
    #[allow(dead_code)]
    pub async fn approved_match_features(
        &self,
        tenant_id: Uuid,
        limit:     i64,
    ) -> Result<Vec<serde_json::Value>> {
        let rows = sqlx::query(
            r#"
            SELECT feature_vector
            FROM ai.steward_feedback
            WHERE tenant_id      = $1
              AND feedback_type  = 'match_approved'
              AND used_in_training = FALSE
            ORDER BY created_at DESC
            LIMIT $2
            "#,
        )
        .bind(tenant_id)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows.into_iter()
            .map(|r| r.try_get("feature_vector").unwrap_or(serde_json::Value::Null))
            .collect())
    }
}
