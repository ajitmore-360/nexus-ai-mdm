use chrono::Utc;

use serde_json::Value;

use sqlx::{
    PgPool,
    Row,
};

use uuid::Uuid;

use contracts::mdm::{
    common::{
        ConfidenceScore,
        MetadataMap,
    },
    matching::{
        FieldMatchResult,
        MatchCandidate,
        MatchStatus,
        MatchStrategy,
    },
};

//
// ========================================
// MATCHING REPOSITORY
// ========================================
//

#[derive(Clone)]
pub struct MatchingRepository {

    pub pool: PgPool,
}

impl MatchingRepository {

    //
    // ====================================
    // CONSTRUCTOR
    // ====================================
    //

    pub fn new(
        pool: PgPool,
    ) -> Self {

        Self {
            pool,
        }
    }

    //
    // ====================================
    // CREATE MATCH CANDIDATE
    // ====================================
    //

    pub async fn create_match_candidate(
        &self,
        tenant_id: Uuid,
        request_id: Uuid,
        source_entity_id: Uuid,
        candidate: &MatchCandidate,
    ) -> Result<(), sqlx::Error> {

        let mut tx =
            self.pool.begin().await?;

        //
        // ====================================
        // INSERT MATCH CANDIDATE
        // ====================================
        //

        sqlx::query(
            r#"
            INSERT INTO core_mdm.match_candidates
            (
                tenant_id,
                match_candidate_id,
                request_id,
                source_entity_id,
                matched_entity_id,
                match_status,
                match_score,
                confidence_score,
                vector_similarity,
                graph_similarity,
                ai_score,
                survivorship_compatibility,
                recommended_for_merge,
                requires_human_review,
                explanations,
                policy_decisions,
                metadata,
                created_at
            )
            VALUES
            (
                $1,
                $2,
                $3,
                $4,
                $5,
                $6,
                $7,
                $8,
                $9,
                $10,
                $11,
                $12,
                $13,
                $14,
                $15,
                $16,
                $17,
                NOW()
            )
            "#
        )
        .bind(tenant_id)
        .bind(Uuid::new_v4())
        .bind(request_id)
        .bind(source_entity_id)
        .bind(candidate.entity_id)
        .bind(format!(
            "{:?}",
            candidate.status
        ))
        .bind(candidate.score)
        .bind(candidate.confidence)
        .bind(candidate.vector_similarity)
        .bind(candidate.graph_similarity)
        .bind(candidate.ai_score)
        .bind(
            candidate
                .survivorship_compatibility
        )
        .bind(
            candidate
                .recommended_for_merge
        )
        .bind(
            candidate
                .requires_human_review
        )
        .bind(
            sqlx::types::Json(
                &candidate.explanations
            )
        )
        .bind(
            sqlx::types::Json(
                &candidate.policy_decisions
            )
        )
        .bind(
            sqlx::types::Json(
                &candidate.metadata
            )
        )
        .execute(&mut *tx)
        .await?;

        //
        // ====================================
        // STORE FIELD MATCH RESULTS
        // ====================================
        //

        for field_match
        in &candidate.field_matches
        {
            sqlx::query(
                r#"
                INSERT INTO core_mdm.field_match_results
                (
                    tenant_id,
                    field_match_id,
                    request_id,
                    source_entity_id,
                    matched_entity_id,
                    field_name,
                    source_value,
                    candidate_value,
                    score,
                    confidence_score,
                    strategy,
                    semantic_similarity,
                    explanation,
                    metadata,
                    created_at
                )
                VALUES
                (
                    $1,
                    $2,
                    $3,
                    $4,
                    $5,
                    $6,
                    $7,
                    $8,
                    $9,
                    $10,
                    $11,
                    $12,
                    $13,
                    $14,
                    NOW()
                )
                "#
            )
            .bind(tenant_id)
            .bind(Uuid::new_v4())
            .bind(request_id)
            .bind(source_entity_id)
            .bind(candidate.entity_id)
            .bind(&field_match.field)
            .bind(
                field_match
                    .source_value
                    .as_ref()
                    .map(sqlx::types::Json)
            )
            .bind(
                field_match
                    .candidate_value
                    .as_ref()
                    .map(sqlx::types::Json)
            )
            .bind(field_match.score)
            .bind(
                field_match
                    .confidence
                    .as_ref()
                    .map(|c| c.score)
            )
            .bind(format!(
                "{:?}",
                field_match.strategy
            ))
            .bind(
                field_match
                    .semantic_similarity
            )
            .bind(
                sqlx::types::Json(
                    &field_match.explanation
                )
            )
            .bind(
                sqlx::types::Json(
                    &field_match.metadata
                )
            )
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;

        Ok(())
    }

    //
    // ====================================
    // FETCH MATCH CANDIDATES
    // ====================================
    //

    pub async fn fetch_match_candidates(
        &self,
        tenant_id: Uuid,
        request_id: Uuid,
    ) -> Result<
        Vec<MatchCandidate>,
        sqlx::Error,
    > {

        let rows =
            sqlx::query(
                r#"
                SELECT
                    matched_entity_id,
                    match_status,
                    match_score,
                    confidence_score,
                    vector_similarity,
                    graph_similarity,
                    ai_score,
                    survivorship_compatibility,
                    recommended_for_merge,
                    requires_human_review,
                    explanations,
                    policy_decisions,
                    metadata
                FROM core_mdm.match_candidates
                WHERE tenant_id = $1
                AND request_id = $2
                ORDER BY match_score DESC
                "#
            )
            .bind(tenant_id)
            .bind(request_id)
            .fetch_all(&self.pool)
            .await?;

        let mut candidates =
            Vec::new();

        for row in rows {

            let entity_id: Uuid =
                row.try_get(
                    "matched_entity_id"
                )?;

            let field_matches =
                self.fetch_field_matches(
                    tenant_id,
                    request_id,
                    entity_id,
                )
                .await?;

            let status_string: String =
                row.try_get(
                    "match_status"
                )?;

            candidates.push(
                MatchCandidate {

                    entity_id,

                    status:
                        parse_match_status(
                            &status_string
                        ),

                    score:
                        row.try_get(
                            "match_score"
                        )?,

                    confidence:
                        row.try_get(
                            "confidence_score"
                        )?,

                    vector_similarity:
                        row.try_get(
                            "vector_similarity"
                        )?,

                    graph_similarity:
                        row.try_get(
                            "graph_similarity"
                        )?,

                    ai_score:
                        row.try_get(
                            "ai_score"
                        )?,

                    survivorship_compatibility:
                        row.try_get(
                            "survivorship_compatibility"
                        )?,

                    explanations:
                        row
                            .try_get::<
                                sqlx::types::Json<
                                    Vec<String>
                                >,
                                _
                            >(
                                "explanations"
                            )
                            .map(|v| v.0)
                            .unwrap_or_default(),

                    field_matches,

                    policy_decisions:
                        row
                            .try_get::<
                                sqlx::types::Json<
                                    Vec<String>
                                >,
                                _
                            >(
                                "policy_decisions"
                            )
                            .map(|v| v.0)
                            .unwrap_or_default(),

                    recommended_for_merge:
                        row.try_get(
                            "recommended_for_merge"
                        )?,

                    requires_human_review:
                        row.try_get(
                            "requires_human_review"
                        )?,

                    metadata:
                        row
                            .try_get::<
                                sqlx::types::Json<
                                    MetadataMap
                                >,
                                _
                            >(
                                "metadata"
                            )
                            .map(|v| v.0)
                            .unwrap_or_default(),
                }
            );
        }

        Ok(candidates)
    }

    //
    // ====================================
    // FETCH FIELD MATCH RESULTS
    // ====================================
    //

    async fn fetch_field_matches(
        &self,
        tenant_id: Uuid,
        request_id: Uuid,
        matched_entity_id: Uuid,
    ) -> Result<
        Vec<FieldMatchResult>,
        sqlx::Error,
    > {

        let rows =
            sqlx::query(
                r#"
                SELECT
                    field_name,
                    source_value,
                    candidate_value,
                    score,
                    confidence_score,
                    strategy,
                    semantic_similarity,
                    explanation,
                    metadata
                FROM core_mdm.field_match_results
                WHERE tenant_id = $1
                AND request_id = $2
                AND matched_entity_id = $3
                ORDER BY created_at ASC
                "#
            )
            .bind(tenant_id)
            .bind(request_id)
            .bind(matched_entity_id)
            .fetch_all(&self.pool)
            .await?;

        let mut field_matches =
            Vec::new();

        for row in rows {

            let strategy_string: String =
                row.try_get(
                    "strategy"
                )?;

            let confidence_score:
                Option<f32> =
                row.try_get(
                    "confidence_score"
                )?;

            field_matches.push(
                FieldMatchResult {

                    field:
                        row.try_get(
                            "field_name"
                        )?,

                    source_value:
                        row
                            .try_get::<
                                Option<
                                    sqlx::types::Json<
                                        Value
                                    >
                                >,
                                _
                            >(
                                "source_value"
                            )
                            .map(|v| {
                                v.map(|j| j.0)
                            })?,

                    candidate_value:
                        row
                            .try_get::<
                                Option<
                                    sqlx::types::Json<
                                        Value
                                    >
                                >,
                                _
                            >(
                                "candidate_value"
                            )
                            .map(|v| {
                                v.map(|j| j.0)
                            })?,

                    score:
                        row.try_get(
                            "score"
                        )?,

                    confidence:
                        confidence_score
                            .map(|score| {

                                ConfidenceScore {

                                    score,

                                    explanation:
                                        None,

                                    model_version:
                                        None,
                                }
                            }),

                    strategy:
                        parse_match_strategy(
                            &strategy_string
                        ),

                    semantic_similarity:
                        row.try_get(
                            "semantic_similarity"
                        )?,

                    explanation:
                        row
                            .try_get::<
                                sqlx::types::Json<
                                    Vec<String>
                                >,
                                _
                            >(
                                "explanation"
                            )
                            .map(|v| v.0)
                            .unwrap_or_default(),

                    metadata:
                        row
                            .try_get::<
                                sqlx::types::Json<
                                    MetadataMap
                                >,
                                _
                            >(
                                "metadata"
                            )
                            .map(|v| v.0)
                            .unwrap_or_default(),
                }
            );
        }

        Ok(field_matches)
    }

    //
    // ====================================
    // DELETE MATCH REQUEST
    // ====================================
    //

    pub async fn delete_match_request(
        &self,
        tenant_id: Uuid,
        request_id: Uuid,
    ) -> Result<u64, sqlx::Error> {

        let result =
            sqlx::query(
                r#"
                DELETE FROM core_mdm.match_candidates
                WHERE tenant_id = $1
                AND request_id = $2
                "#
            )
            .bind(tenant_id)
            .bind(request_id)
            .execute(&self.pool)
            .await?;

        Ok(
            result.rows_affected()
        )
    }

    //
    // ====================================
    // COUNT MATCHES
    // ====================================
    //

    pub async fn count_matches(
        &self,
        tenant_id: Uuid,
    ) -> Result<i64, sqlx::Error> {

        let row =
            sqlx::query(
                r#"
                SELECT COUNT(*)
                FROM core_mdm.match_candidates
                WHERE tenant_id = $1
                "#
            )
            .bind(tenant_id)
            .fetch_one(&self.pool)
            .await?;

        Ok(
            row.get::<i64, _>(0)
        )
    }

    //
    // ====================================
    // FETCH HUMAN REVIEW QUEUE
    // ====================================
    //

    pub async fn fetch_review_queue(
        &self,
        tenant_id: Uuid,
        limit: i64,
    ) -> Result<
        Vec<MatchCandidate>,
        sqlx::Error,
    > {

        let rows =
            sqlx::query(
                r#"
                SELECT DISTINCT
                    request_id
                FROM core_mdm.match_candidates
                WHERE tenant_id = $1
                AND requires_human_review = TRUE
                ORDER BY created_at DESC
                LIMIT $2
                "#
            )
            .bind(tenant_id)
            .bind(limit)
            .fetch_all(&self.pool)
            .await?;

        let mut all_matches =
            Vec::new();

        for row in rows {

            let request_id: Uuid =
                row.try_get(
                    "request_id"
                )?;

            let matches =
                self.fetch_match_candidates(
                    tenant_id,
                    request_id,
                )
                .await?;

            all_matches.extend(matches);
        }

        Ok(all_matches)
    }
}

//
// ========================================
// PARSE MATCH STATUS
// ========================================
//

fn parse_match_status(
    value: &str,
) -> MatchStatus {

    match value {

        "Pending" => {
            MatchStatus::Pending
        }

        "Matched" => {
            MatchStatus::Matched
        }

        "PossibleMatch" => {
            MatchStatus::PossibleMatch
        }

        "RequiresReview" => {
            MatchStatus::RequiresReview
        }

        "Rejected" => {
            MatchStatus::Rejected
        }

        "AutoMerged" => {
            MatchStatus::AutoMerged
        }

        _ => {
            MatchStatus::Pending
        }
    }
}

//
// ========================================
// PARSE MATCH STRATEGY
// ========================================
//

fn parse_match_strategy(
    value: &str,
) -> MatchStrategy {

    match value {

        "Deterministic" => {
            MatchStrategy::Deterministic
        }

        "Fuzzy" => {
            MatchStrategy::Fuzzy
        }

        "AIEnhanced" => {
            MatchStrategy::AIEnhanced
        }

        "Hybrid" => {
            MatchStrategy::Hybrid
        }

        "Semantic" => {
            MatchStrategy::Semantic
        }

        "Graph" => {
            MatchStrategy::Graph
        }

        "Ensemble" => {
            MatchStrategy::Ensemble
        }

        custom => {
            MatchStrategy::Custom(
                custom.to_string()
            )
        }
    }
}