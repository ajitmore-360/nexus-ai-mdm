use std::collections::{HashMap, HashSet};

use serde_json::Value;

use sqlx::{
    PgPool,
    Row,
};

use uuid::Uuid;

use contracts::mdm::entity::CanonicalEntity;

use crate::db::repositories::entity_repository::EntityRepository;

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
                $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
                $11, $12, $13, $14, $15, $16, $17, NOW()
            )
            "#
        )
        .bind(tenant_id)
        .bind(Uuid::new_v4())
        .bind(request_id)
        .bind(source_entity_id)
        .bind(candidate.entity_id)
        .bind(match_status_to_db(&candidate.status))
        .bind(candidate.score)
        .bind(candidate.confidence)
        .bind(candidate.vector_similarity)
        .bind(candidate.graph_similarity)
        .bind(candidate.ai_score)
        .bind(candidate.survivorship_compatibility)
        .bind(candidate.recommended_for_merge)
        .bind(candidate.requires_human_review)
        .bind(sqlx::types::Json(&candidate.explanations))
        .bind(sqlx::types::Json(&candidate.policy_decisions))
        .bind(sqlx::types::Json(&candidate.metadata))
        .execute(&mut *tx)
        .await?;

        for field_match in &candidate.field_matches {
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
                    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
                    $11, $12, $13, $14, NOW()
                )
                "#
            )
            .bind(tenant_id)
            .bind(Uuid::new_v4())
            .bind(request_id)
            .bind(source_entity_id)
            .bind(candidate.entity_id)
            .bind(&field_match.field)
            .bind(field_match.source_value.as_ref().map(sqlx::types::Json))
            .bind(field_match.candidate_value.as_ref().map(sqlx::types::Json))
            .bind(field_match.score)
            .bind(field_match.confidence.as_ref().map(|c| c.score))
            .bind(match_strategy_to_db(&field_match.strategy))
            .bind(field_match.semantic_similarity)
            .bind(sqlx::types::Json(&field_match.explanation))
            .bind(sqlx::types::Json(&field_match.metadata))
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;

        Ok(())
    }

    //
    // ====================================
    // FETCH MATCH CANDIDATES (single JOIN — no N+1)
    // ====================================
    //

    pub async fn fetch_match_candidates(
        &self,
        tenant_id: Uuid,
        request_id: Uuid,
    ) -> Result<Vec<MatchCandidate>, sqlx::Error> {

        // One query fetches candidates and all their field matches together.
        // Rows are ordered so all field rows for a candidate follow its first row.
        let rows = sqlx::query(
            r#"
            SELECT
                mc.matched_entity_id,
                mc.match_status,
                mc.match_score,
                mc.confidence_score,
                mc.vector_similarity,
                mc.graph_similarity,
                mc.ai_score,
                mc.survivorship_compatibility,
                mc.recommended_for_merge,
                mc.requires_human_review,
                mc.explanations,
                mc.policy_decisions,
                mc.metadata,
                fm.field_name,
                fm.source_value,
                fm.candidate_value,
                fm.score            AS fm_score,
                fm.confidence_score AS fm_confidence,
                fm.strategy,
                fm.semantic_similarity,
                fm.explanation,
                fm.metadata         AS fm_metadata
            FROM core_mdm.match_candidates mc
            LEFT JOIN core_mdm.field_match_results fm
                ON  fm.tenant_id   = mc.tenant_id
                AND fm.request_id  = mc.request_id
                AND fm.matched_entity_id = mc.matched_entity_id
            WHERE mc.tenant_id  = $1
              AND mc.request_id = $2
            ORDER BY mc.match_score DESC, fm.created_at ASC
            "#
        )
        .bind(tenant_id)
        .bind(request_id)
        .fetch_all(&self.pool)
        .await?;

        // Group field-match rows by candidate entity id, preserving score order.
        let mut order: Vec<Uuid> = Vec::new();
        let mut candidate_rows: HashMap<Uuid, _> = HashMap::new();
        let mut field_rows: HashMap<Uuid, Vec<_>> = HashMap::new();

        for row in &rows {
            let entity_id: Uuid = row.try_get("matched_entity_id")?;

            if let std::collections::hash_map::Entry::Vacant(e) = candidate_rows.entry(entity_id) {
                order.push(entity_id);
                e.insert(row);
            }

            // Only push a field row if a field_name is present (LEFT JOIN may produce NULLs).
            let field_name: Option<String> = row.try_get("field_name").ok().flatten();
            if field_name.is_some() {
                field_rows.entry(entity_id).or_default().push(row);
            }
        }

        let mut candidates = Vec::with_capacity(order.len());

        for entity_id in order {
            let row = candidate_rows[&entity_id];

            let status_string: String = row.try_get("match_status")?;

            // Reconstruct field matches from the grouped rows.
            let field_matches: Vec<FieldMatchResult> = field_rows
                .get(&entity_id)
                .map(|frs| {
                    frs.iter()
                        .filter_map(|fr| build_field_match(fr).ok())
                        .collect()
                })
                .unwrap_or_default();

            candidates.push(MatchCandidate {
                entity_id,

                status: parse_match_status(&status_string),

                score: row.try_get("match_score")?,

                confidence: row.try_get("confidence_score")?,

                vector_similarity: row.try_get("vector_similarity")?,

                graph_similarity: row.try_get("graph_similarity")?,

                ai_score: row.try_get("ai_score")?,

                survivorship_compatibility: row.try_get("survivorship_compatibility")?,

                explanations: row
                    .try_get::<sqlx::types::Json<Vec<String>>, _>("explanations")
                    .map(|v| v.0)
                    .unwrap_or_default(),

                field_matches,

                policy_decisions: row
                    .try_get::<sqlx::types::Json<Vec<String>>, _>("policy_decisions")
                    .map(|v| v.0)
                    .unwrap_or_default(),

                recommended_for_merge: row.try_get("recommended_for_merge")?,

                requires_human_review: row.try_get("requires_human_review")?,

                metadata: row
                    .try_get::<sqlx::types::Json<MetadataMap>, _>("metadata")
                    .map(|v| v.0)
                    .unwrap_or_default(),
            });
        }

        Ok(candidates)
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

        Ok(result.rows_affected())
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

        Ok(row.get::<i64, _>(0))
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
        offset: i64,
    ) -> Result<Vec<MatchCandidate>, sqlx::Error> {

        let rows = sqlx::query(
            r#"
            SELECT DISTINCT request_id
            FROM core_mdm.match_candidates
            WHERE tenant_id = $1
              AND requires_human_review = TRUE
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#
        )
        .bind(tenant_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        let mut all_matches = Vec::new();

        for row in rows {
            let request_id: Uuid = row.try_get("request_id")?;
            let matches = self.fetch_match_candidates(tenant_id, request_id).await?;
            all_matches.extend(matches);
        }

        Ok(all_matches)
    }

    //
    // ====================================
    // BLOCKING KEY LOOKUP
    // ====================================
    //

    pub async fn find_by_blocking_keys(
        &self,
        tenant_id: Uuid,
        keys: &[String],
        limit: usize,
    ) -> Result<HashSet<Uuid>, sqlx::Error> {
        let mut entity_ids = HashSet::new();

        for key in keys {
            let Some((kind, value)) = key.split_once(':') else {
                continue;
            };

            let attribute_key = match kind {
                "EMAIL"    => "email",
                "PHONE"    => "phone",
                "TAX"      => "tax_id",
                "CID"      => "customer_id",
                "VID"      => "vendor_id",
                "PHONETIC" => "name",
                _          => continue,
            };

            let rows = sqlx::query_scalar::<_, Uuid>(
                r#"
                SELECT DISTINCT entity_id
                FROM core_mdm.entity_attributes
                WHERE tenant_id = $1
                  AND attribute_key = $2
                  AND lower(trim(both '"' from attribute_value::text)) = $3
                LIMIT $4
                "#,
            )
            .bind(tenant_id)
            .bind(attribute_key)
            .bind(value)
            .bind(limit as i64)
            .fetch_all(&self.pool)
            .await?;

            entity_ids.extend(rows);
        }

        Ok(entity_ids)
    }

    //
    // ====================================
    // LOAD ENTITIES FOR SCORING
    // ====================================
    //

    pub async fn load_entities(
        &self,
        tenant_id: Uuid,
        candidate_ids: &HashSet<Uuid>,
    ) -> anyhow::Result<Vec<CanonicalEntity>> {
        let entity_repo = EntityRepository::new(self.pool.clone());
        let mut entities = Vec::with_capacity(candidate_ids.len());

        for entity_id in candidate_ids {
            if let Some(entity) =
                entity_repo.fetch_entity(tenant_id, *entity_id).await?
            {
                entities.push(entity);
            }
        }

        Ok(entities)
    }

    // ====================================
    // UPDATE CANDIDATE STATUS
    // ====================================

    pub async fn update_candidate_status(
        &self,
        tx:           &mut sqlx::Transaction<'_, sqlx::Postgres>,
        tenant_id:    Uuid,
        request_id:   Uuid,
        candidate_id: Uuid,
        status:       &str,
    ) -> anyhow::Result<()> {
        sqlx::query(
            r#"
            UPDATE core_mdm.match_candidates
            SET    match_status = $4,
                   updated_at  = NOW()
            WHERE  tenant_id          = $1
            AND    request_id         = $2
            AND    matched_entity_id  = $3
            "#,
        )
        .bind(tenant_id)
        .bind(request_id)
        .bind(candidate_id)
        .bind(status)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }
}

//
// ========================================
// BUILD FIELD MATCH FROM A JOIN ROW
// ========================================
//

fn build_field_match(row: &sqlx::postgres::PgRow) -> Result<FieldMatchResult, sqlx::Error> {
    let strategy_str: String = row.try_get("strategy")?;
    let confidence_score: Option<f32> = row.try_get("fm_confidence")?;

    Ok(FieldMatchResult {
        field: row.try_get("field_name")?,

        source_value: row
            .try_get::<Option<sqlx::types::Json<Value>>, _>("source_value")
            .map(|v| v.map(|j| j.0))?,

        candidate_value: row
            .try_get::<Option<sqlx::types::Json<Value>>, _>("candidate_value")
            .map(|v| v.map(|j| j.0))?,

        score: row.try_get("fm_score")?,

        confidence: confidence_score.map(|score| ConfidenceScore {
            score,
            explanation: None,
            model_version: None,
        }),

        strategy: parse_match_strategy(&strategy_str),

        semantic_similarity: row.try_get("semantic_similarity")?,

        explanation: row
            .try_get::<sqlx::types::Json<Vec<String>>, _>("explanation")
            .map(|v| v.0)
            .unwrap_or_default(),

        metadata: row
            .try_get::<sqlx::types::Json<MetadataMap>, _>("fm_metadata")
            .map(|v| v.0)
            .unwrap_or_default(),
    })
}

//
// ========================================
// ENUM → DB STRING  (explicit, rename-safe)
// ========================================
//

fn match_status_to_db(status: &MatchStatus) -> &'static str {
    match status {
        MatchStatus::Pending        => "Pending",
        MatchStatus::Matched        => "Matched",
        MatchStatus::PossibleMatch  => "PossibleMatch",
        MatchStatus::RequiresReview => "RequiresReview",
        MatchStatus::Rejected       => "Rejected",
        MatchStatus::AutoMerged     => "AutoMerged",
    }
}

fn match_strategy_to_db(strategy: &MatchStrategy) -> String {
    match strategy {
        MatchStrategy::Deterministic => "Deterministic".to_string(),
        MatchStrategy::Fuzzy         => "Fuzzy".to_string(),
        MatchStrategy::AIEnhanced    => "AIEnhanced".to_string(),
        MatchStrategy::Hybrid        => "Hybrid".to_string(),
        MatchStrategy::Semantic      => "Semantic".to_string(),
        MatchStrategy::Graph         => "Graph".to_string(),
        MatchStrategy::Ensemble      => "Ensemble".to_string(),
        MatchStrategy::Custom(s)     => s.clone(),
    }
}

//
// ========================================
// DB STRING → ENUM
// ========================================
//

fn parse_match_status(value: &str) -> MatchStatus {
    match value {
        "Pending"        => MatchStatus::Pending,
        "Matched"        => MatchStatus::Matched,
        "PossibleMatch"  => MatchStatus::PossibleMatch,
        "RequiresReview" => MatchStatus::RequiresReview,
        "Rejected"       => MatchStatus::Rejected,
        "AutoMerged"     => MatchStatus::AutoMerged,
        unknown => {
            tracing::warn!(value=%unknown, "unrecognised match_status in DB; defaulting to Pending");
            MatchStatus::Pending
        }
    }
}

fn parse_match_strategy(value: &str) -> MatchStrategy {
    match value {
        "Deterministic" => MatchStrategy::Deterministic,
        "Fuzzy"         => MatchStrategy::Fuzzy,
        "AIEnhanced"    => MatchStrategy::AIEnhanced,
        "Hybrid"        => MatchStrategy::Hybrid,
        "Semantic"      => MatchStrategy::Semantic,
        "Graph"         => MatchStrategy::Graph,
        "Ensemble"      => MatchStrategy::Ensemble,
        custom          => MatchStrategy::Custom(custom.to_string()),
    }
}
