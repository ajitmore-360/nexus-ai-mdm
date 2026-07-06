use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::llm::{OllamaClient, Prompts};

#[derive(Debug, Deserialize)]
pub struct SuggestRulesArgs {
    pub entity_type: String,
    pub field_name:  Option<String>,
}

#[derive(Debug, Serialize)]
pub struct RuleSuggestion {
    pub field_name:  String,
    pub strategy:    String,
    pub primary_source: Option<String>,
    pub confidence:  f32,
    pub reasoning:   String,
}

/// Analyse historical merge decisions and suggest survivorship rules via Llama.
pub async fn suggest_survivorship_rules(
    pool:      &PgPool,
    llm:       &OllamaClient,
    tenant_id: Uuid,
    args:      SuggestRulesArgs,
) -> Result<Value> {
    // Load merge history for this entity type (last 500 decisions)
    let history_rows = sqlx::query(
        r#"
        SELECT
            sf.feature_vector,
            sf.human_decision,
            sf.system_decision
        FROM ai.steward_feedback sf
        WHERE sf.tenant_id    = $1
          AND sf.feedback_type IN ('match_approved', 'merge_overridden')
        ORDER BY sf.created_at DESC
        LIMIT 500
        "#,
    )
    .bind(tenant_id)
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    let merge_history: Vec<Value> = history_rows
        .iter()
        .filter_map(|r| r.try_get::<Value, _>("feature_vector").ok())
        .collect();

    // Load source trust scores
    let trust_rows = sqlx::query(
        r#"
        SELECT source_system, AVG(trust_score)::FLOAT8 AS avg_trust
        FROM core_mdm.entities
        WHERE tenant_id   = $1
          AND entity_type = $2
        GROUP BY source_system
        ORDER BY avg_trust DESC
        LIMIT 10
        "#,
    )
    .bind(tenant_id)
    .bind(&args.entity_type)
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    let source_trust: serde_json::Map<String, Value> = trust_rows
        .iter()
        .filter_map(|r| {
            let src: Option<String> = r.try_get("source_system").ok().flatten();
            let src = src?;
            let trust: f64  = r.try_get("avg_trust").ok().flatten().unwrap_or(0.0);
            Some((src, Value::from(trust)))
        })
        .collect();

    // Determine which fields to suggest rules for
    let fields_to_analyse = if let Some(f) = &args.field_name {
        vec![f.clone()]
    } else {
        // Infer from entity type common fields
        match args.entity_type.to_lowercase().as_str() {
            "customer" => vec![
                "legal_name".into(), "email".into(), "phone".into(),
                "address".into(), "tax_id".into(), "revenue".into(),
            ],
            "vendor" => vec![
                "legal_name".into(), "email".into(), "tax_id".into(),
                "payment_terms".into(),
            ],
            _ => vec!["name".into(), "email".into()],
        }
    };

    let mut suggestions = Vec::new();

    for field in &fields_to_analyse {
        let prompt = Prompts::suggest_survivorship_rules(
            field,
            &args.entity_type,
            &Value::Array(merge_history.clone()),
            &Value::Object(source_trust.clone()),
        );

        match llm.generate(&prompt, false).await {
            Ok(raw) => {
                if let Some(s) = parse_suggestion(field, &raw) {
                    suggestions.push(s);
                }
            }
            Err(e) => {
                tracing::warn!(field=%field, error=%e, "LLM suggestion failed; skipping field");
            }
        }
    }

    Ok(serde_json::json!({
        "entity_type": args.entity_type,
        "suggestions": suggestions,
        "suggestion_count": suggestions.len(),
        "based_on_decisions": merge_history.len(),
    }))
}

fn parse_suggestion(field: &str, raw: &str) -> Option<RuleSuggestion> {
    let start = raw.find('{')?;
    let end   = raw.rfind('}').map(|i| i + 1)?;
    let json: Value = serde_json::from_str(&raw[start..end]).ok()?;

    Some(RuleSuggestion {
        field_name:     field.to_string(),
        strategy:       json.get("strategy")?.as_str()?.to_string(),
        primary_source: json.get("primary_source").and_then(|v| v.as_str()).map(str::to_owned),
        confidence:     json.get("confidence")?.as_f64()? as f32,
        reasoning:      json.get("reasoning")?.as_str()?.to_string(),
    })
}
