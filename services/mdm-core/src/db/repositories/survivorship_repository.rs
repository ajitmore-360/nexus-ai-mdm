use serde_json::Value;

use sqlx::{
    PgPool,
    Postgres,
    Row,
    Transaction,
};

use uuid::Uuid;

use contracts::mdm::survivorship::{
    SurvivorshipEvaluation,
    SurvivorshipExecutionMetadata,
    SurvivorshipExecutionResult,
    SurvivorshipRule,
    SurvivorshipScope,
    SurvivorshipStatus,
    SurvivorshipStrategy,
};

//
// ========================================
// SURVIVORSHIP REPOSITORY
// ========================================
//

#[derive(Clone)]
pub struct SurvivorshipRepository {

    pub pool: PgPool,
}

impl SurvivorshipRepository {

    //
    // ====================================
    // CONSTRUCTOR
    // ====================================
    //

    pub fn new(
        pool: PgPool,
    ) -> Self {

        Self { pool }
    }

    //
    // ====================================
    // CREATE EXECUTION RESULT
    // ====================================
    //

    pub async fn create_execution_result(
        &self,
        tenant_id: Uuid,
        result: &SurvivorshipExecutionResult,
        execution_metadata: &SurvivorshipExecutionMetadata,
        golden_record_id: Option<Uuid>,
        applied_rules: &[SurvivorshipRule],
    ) -> Result<(), sqlx::Error> {

        let mut tx =
            self.pool.begin().await?;

        //
        // STORE EXECUTION
        //

        sqlx::query(
            r#"
            INSERT INTO core_mdm.survivorship_executions
            (
                tenant_id,
                execution_id,
                golden_record_id,
                success,
                overall_confidence,
                execution_time_ms,
                summary,
                warnings,
                errors,
                evaluated_rules,
                evaluated_candidates,
                ai_assisted,
                explainability_enabled,
                engine_version,
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
                NOW()
            )
            "#
        )
        .bind(tenant_id)
        .bind(result.execution_id)
        .bind(golden_record_id)
        .bind(result.success)
        .bind(result.overall_confidence)
        .bind(result.execution_time_ms as i64)
        .bind(&result.summary)
        .bind(
            serde_json::to_value(
                &result.warnings
            )
            .unwrap_or(Value::Null)
        )
        .bind(
            serde_json::to_value(
                &result.errors
            )
            .unwrap_or(Value::Null)
        )
        .bind(
            execution_metadata
                .evaluated_rules as i64
        )
        .bind(
            execution_metadata
                .evaluated_candidates as i64
        )
        .bind(
            execution_metadata
                .ai_assisted
        )
        .bind(
            execution_metadata
                .explainability_enabled
        )
        .bind(
            &execution_metadata
                .engine_version
        )
        .bind(
            serde_json::to_value(
                &execution_metadata
                    .metadata
            )
            .unwrap_or(Value::Null)
        )
        .execute(&mut *tx)
        .await?;

        //
        // STORE EVALUATIONS
        //

        for evaluation
        in &result.evaluations
        {
            self.insert_evaluation(
                &mut tx,
                tenant_id,
                result.execution_id,
                evaluation,
            )
            .await?;
        }

        //
        // STORE RULE AUDIT
        //

        for rule
        in applied_rules
        {
            self.insert_rule_audit(
                &mut tx,
                tenant_id,
                result.execution_id,
                rule,
            )
            .await?;
        }

        tx.commit().await?;

        Ok(())
    }

    //
    // ====================================
    // INSERT EVALUATION
    // ====================================
    //

    async fn insert_evaluation(
        &self,
        tx: &mut Transaction<
            '_,
            Postgres,
        >,
        tenant_id: Uuid,
        execution_id: Uuid,
        evaluation: &SurvivorshipEvaluation,
    ) -> Result<(), sqlx::Error> {

        sqlx::query(
            r#"
            INSERT INTO core_mdm.survivorship_evaluations
            (
                tenant_id,
                evaluation_id,
                execution_id,
                rule_id,
                attribute,
                selected_value,
                selected_source,
                confidence,
                survivorship_score,
                ai_score,
                reasoning,
                policy_decisions,
                warnings,
                manually_overridden,
                overridden_by,
                overridden_at,
                evaluated_at,
                metadata
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
                $18
            )
            "#
        )
        .bind(tenant_id)
        .bind(evaluation.evaluation_id)
        .bind(execution_id)
        .bind(evaluation.rule_id)
        .bind(&evaluation.attribute)
        .bind(
            serde_json::to_value(
                &evaluation.selected_value
            )
            .unwrap_or(Value::Null)
        )
        .bind(
            &evaluation.selected_source
        )
        .bind(evaluation.confidence)
        .bind(
            evaluation
                .survivorship_score
        )
        .bind(evaluation.ai_score)
        .bind(&evaluation.reasoning)
        .bind(
            serde_json::to_value(
                &evaluation
                    .policy_decisions
            )
            .unwrap_or(Value::Null)
        )
        .bind(
            serde_json::to_value(
                &evaluation.warnings
            )
            .unwrap_or(Value::Null)
        )
        .bind(
            evaluation
                .manually_overridden
        )
        .bind(evaluation.overridden_by)
        .bind(evaluation.overridden_at)
        .bind(evaluation.evaluated_at)
        .bind(
            serde_json::to_value(
                &evaluation.metadata
            )
            .unwrap_or(Value::Null)
        )
        .execute(&mut **tx)
        .await?;

        Ok(())
    }

    //
    // ====================================
    // INSERT RULE AUDIT
    // ====================================
    //

    async fn insert_rule_audit(
        &self,
        tx: &mut Transaction<
            '_,
            Postgres,
        >,
        tenant_id: Uuid,
        execution_id: Uuid,
        rule: &SurvivorshipRule,
    ) -> Result<(), sqlx::Error> {

        sqlx::query(
            r#"
            INSERT INTO core_mdm.survivorship_rules_audit
            (
                tenant_id,
                audit_id,
                execution_id,
                rule_id,
                rule_name,
                attribute,
                strategy,
                scope,
                priority,
                status,
                ai_assisted,
                explainability_enabled,
                allow_manual_override,
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
        .bind(execution_id)
        .bind(rule.rule_id)
        .bind(&rule.rule_name)
        .bind(&rule.attribute)
        .bind(strategy_to_string(
            &rule.strategy
        ))
        .bind(scope_to_string(
            &rule.scope
        ))
        .bind(rule.priority)
        .bind(status_to_string(
            &rule.status
        ))
        .bind(rule.ai_assisted)
        .bind(
            rule
                .explainability_enabled
        )
        .bind(
            rule
                .allow_manual_override
        )
        .bind(
            serde_json::to_value(
                &rule.metadata
            )
            .unwrap_or(Value::Null)
        )
        .execute(&mut **tx)
        .await?;

        Ok(())
    }

    //
    // ====================================
    // FETCH EXECUTION METADATA
    // ====================================
    //

    pub async fn fetch_execution_metadata(
        &self,
        tenant_id: Uuid,
        execution_id: Uuid,
    ) -> Result<
        Option<
            SurvivorshipExecutionMetadata
        >,
        sqlx::Error,
    > {

        let row =
            sqlx::query(
                r#"
                SELECT
                    execution_id,
                    evaluated_rules,
                    evaluated_candidates,
                    execution_time_ms,
                    ai_assisted,
                    explainability_enabled,
                    engine_version,
                    metadata
                FROM core_mdm.survivorship_executions
                WHERE tenant_id = $1
                AND execution_id = $2
                "#
            )
            .bind(tenant_id)
            .bind(execution_id)
            .fetch_optional(&self.pool)
            .await?;

        let Some(row) = row else {
            return Ok(None);
        };

        Ok(Some(
            SurvivorshipExecutionMetadata {

                execution_id:
                    row.try_get(
                        "execution_id"
                    )?,

                evaluated_rules:
                    row
                        .try_get::<
                            i64,
                            _
                        >(
                            "evaluated_rules"
                        )? as usize,

                evaluated_candidates:
                    row
                        .try_get::<
                            i64,
                            _
                        >(
                            "evaluated_candidates"
                        )? as usize,

                execution_time_ms:
                    row
                        .try_get::<
                            i64,
                            _
                        >(
                            "execution_time_ms"
                        )? as u64,

                ai_assisted:
                    row.try_get(
                        "ai_assisted"
                    )?,

                explainability_enabled:
                    row.try_get(
                        "explainability_enabled"
                    )?,

                engine_version:
                    row.try_get(
                        "engine_version"
                    )?,

                metadata:
                    serde_json::from_value(
                        row.try_get::<
                            Value,
                            _
                        >("metadata")?
                    )
                    .unwrap_or_default(),
            }
        ))
    }

    //
    // ====================================
    // FETCH EVALUATIONS
    // ====================================
    //

    pub async fn fetch_evaluations(
        &self,
        tenant_id: Uuid,
        execution_id: Uuid,
    ) -> Result<
        Vec<SurvivorshipEvaluation>,
        sqlx::Error,
    > {

        let rows =
            sqlx::query(
                r#"
                SELECT
                    evaluation_id,
                    rule_id,
                    attribute,
                    selected_value,
                    selected_source,
                    confidence,
                    survivorship_score,
                    ai_score,
                    reasoning,
                    policy_decisions,
                    warnings,
                    manually_overridden,
                    overridden_by,
                    overridden_at,
                    evaluated_at,
                    metadata
                FROM core_mdm.survivorship_evaluations
                WHERE tenant_id = $1
                AND execution_id = $2
                ORDER BY evaluated_at ASC
                "#
            )
            .bind(tenant_id)
            .bind(execution_id)
            .fetch_all(&self.pool)
            .await?;

        let mut evaluations =
            Vec::new();

        for row in rows {

            evaluations.push(
                SurvivorshipEvaluation {

                    evaluation_id:
                        row.try_get(
                            "evaluation_id"
                        )?,

                    rule_id:
                        row.try_get(
                            "rule_id"
                        )?,

                    attribute:
                        row.try_get(
                            "attribute"
                        )?,

                    selected_value:
                        row.try_get::<
                            Value,
                            _
                        >(
                            "selected_value"
                        )?,

                    selected_source:
                        row.try_get(
                            "selected_source"
                        )?,

                    confidence:
                        row.try_get(
                            "confidence"
                        )?,

                    survivorship_score:
                        row.try_get(
                            "survivorship_score"
                        )?,

                    ai_score:
                        row.try_get(
                            "ai_score"
                        )?,

                    reasoning:
                        row.try_get(
                            "reasoning"
                        )?,

                    policy_decisions:
                        serde_json::from_value(
                            row.try_get::<
                                Value,
                                _
                            >(
                                "policy_decisions"
                            )?
                        )
                        .unwrap_or_default(),

                    warnings:
                        serde_json::from_value(
                            row.try_get::<
                                Value,
                                _
                            >("warnings")?
                        )
                        .unwrap_or_default(),

                    manually_overridden:
                        row.try_get(
                            "manually_overridden"
                        )?,

                    overridden_by:
                        row.try_get(
                            "overridden_by"
                        )?,

                    overridden_at:
                        row.try_get(
                            "overridden_at"
                        )?,

                    evaluated_at:
                        row.try_get(
                            "evaluated_at"
                        )?,

                    metadata:
                        serde_json::from_value(
                            row.try_get::<
                                Value,
                                _
                            >("metadata")?
                        )
                        .unwrap_or_default(),
                }
            );
        }

        Ok(evaluations)
    }

    //
    // ====================================
    // FETCH EXECUTION HISTORY
    // ====================================
    //

    pub async fn fetch_execution_history(
        &self,
        tenant_id: Uuid,
        limit: i64,
    ) -> Result<
        Vec<
            SurvivorshipExecutionMetadata
        >,
        sqlx::Error,
    > {

        let rows =
            sqlx::query(
                r#"
                SELECT
                    execution_id
                FROM core_mdm.survivorship_executions
                WHERE tenant_id = $1
                ORDER BY created_at DESC
                LIMIT $2
                "#
            )
            .bind(tenant_id)
            .bind(limit)
            .fetch_all(&self.pool)
            .await?;

        let mut executions =
            Vec::new();

        for row in rows {

            let execution_id: Uuid =
                row.try_get(
                    "execution_id"
                )?;

            if let Some(metadata) =
                self.fetch_execution_metadata(
                    tenant_id,
                    execution_id,
                )
                .await?
            {
                executions.push(metadata);
            }
        }

        Ok(executions)
    }

    //
    // ====================================
    // DELETE EXECUTION
    // ====================================
    //

    pub async fn delete_execution(
        &self,
        tenant_id: Uuid,
        execution_id: Uuid,
    ) -> Result<u64, sqlx::Error> {

        let mut tx =
            self.pool.begin().await?;

        sqlx::query(
            r#"
            DELETE FROM core_mdm.survivorship_evaluations
            WHERE tenant_id = $1
            AND execution_id = $2
            "#
        )
        .bind(tenant_id)
        .bind(execution_id)
        .execute(&mut *tx)
        .await?;

        sqlx::query(
            r#"
            DELETE FROM core_mdm.survivorship_rules_audit
            WHERE tenant_id = $1
            AND execution_id = $2
            "#
        )
        .bind(tenant_id)
        .bind(execution_id)
        .execute(&mut *tx)
        .await?;

        let result =
            sqlx::query(
                r#"
                DELETE FROM core_mdm.survivorship_executions
                WHERE tenant_id = $1
                AND execution_id = $2
                "#
            )
            .bind(tenant_id)
            .bind(execution_id)
            .execute(&mut *tx)
            .await?;

        tx.commit().await?;

        Ok(
            result.rows_affected()
        )
    }

    //
    // ====================================
    // COUNT EXECUTIONS
    // ====================================
    //

    pub async fn count_executions(
        &self,
        tenant_id: Uuid,
    ) -> Result<i64, sqlx::Error> {

        let row =
            sqlx::query(
                r#"
                SELECT COUNT(*)
                FROM core_mdm.survivorship_executions
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
}

//
// ========================================
// STRATEGY SERIALIZATION
// ========================================
//

fn strategy_to_string(
    strategy: &SurvivorshipStrategy,
) -> String {

    match strategy {

        SurvivorshipStrategy::MostRecent => {
            "MostRecent".to_string()
        }

        SurvivorshipStrategy::HighestConfidence => {
            "HighestConfidence"
                .to_string()
        }

        SurvivorshipStrategy::TrustedSource => {
            "TrustedSource"
                .to_string()
        }

        SurvivorshipStrategy::LongestValue => {
            "LongestValue".to_string()
        }

        SurvivorshipStrategy::MostComplete => {
            "MostComplete".to_string()
        }

        SurvivorshipStrategy::AIRecommended => {
            "AIRecommended"
                .to_string()
        }

        SurvivorshipStrategy::SemanticSimilarity => {
            "SemanticSimilarity"
                .to_string()
        }

        SurvivorshipStrategy::HybridWeighted => {
            "HybridWeighted"
                .to_string()
        }

        SurvivorshipStrategy::Custom(
            value,
        ) => {
            format!(
                "Custom:{}",
                value
            )
        }
    }
}

//
// ========================================
// PARSE STRATEGY
// ========================================
//

pub fn parse_strategy(
    value: &str,
) -> SurvivorshipStrategy {

    match value {

        "MostRecent" => {
            SurvivorshipStrategy::MostRecent
        }

        "HighestConfidence" => {
            SurvivorshipStrategy::HighestConfidence
        }

        "TrustedSource" => {
            SurvivorshipStrategy::TrustedSource
        }

        "LongestValue" => {
            SurvivorshipStrategy::LongestValue
        }

        "MostComplete" => {
            SurvivorshipStrategy::MostComplete
        }

        "AIRecommended" => {
            SurvivorshipStrategy::AIRecommended
        }

        "SemanticSimilarity" => {
            SurvivorshipStrategy::SemanticSimilarity
        }

        "HybridWeighted" => {
            SurvivorshipStrategy::HybridWeighted
        }

        value
            if value.starts_with(
                "Custom:"
            ) =>
        {
            SurvivorshipStrategy::Custom(
                value
                    .trim_start_matches(
                        "Custom:"
                    )
                    .to_string(),
            )
        }

        _ => {
            SurvivorshipStrategy::MostRecent
        }
    }
}

//
// ========================================
// STATUS SERIALIZATION
// ========================================
//

fn status_to_string(
    status: &SurvivorshipStatus,
) -> String {

    match status {

        SurvivorshipStatus::Draft => {
            "Draft".to_string()
        }

        SurvivorshipStatus::Active => {
            "Active".to_string()
        }

        SurvivorshipStatus::Disabled => {
            "Disabled".to_string()
        }

        SurvivorshipStatus::Deprecated => {
            "Deprecated".to_string()
        }
    }
}

//
// ========================================
// SCOPE SERIALIZATION
// ========================================
//

fn scope_to_string(
    scope: &SurvivorshipScope,
) -> String {

    match scope {

        SurvivorshipScope::Global => {
            "Global".to_string()
        }

        SurvivorshipScope::Tenant => {
            "Tenant".to_string()
        }

        SurvivorshipScope::EntityType(
            value,
        ) => {
            format!(
                "EntityType:{}",
                value
            )
        }

        SurvivorshipScope::Attribute(
            value,
        ) => {
            format!(
                "Attribute:{}",
                value
            )
        }
    }
}