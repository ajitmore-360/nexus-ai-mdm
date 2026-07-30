use std::sync::Arc;
use std::time::Duration;

use uuid::Uuid;
use tracing::{info, warn};
use azile_redis::{TaskQueue, queue::task_types};
use contracts::mdm::matching::{MatchRequest, MatchStrategy};

use crate::AppState;

/// Background worker that consumes `ENTITY_MATCH` tasks from the Redis sorted
/// set and runs the matching engine for each ingested entity.
///
/// After matching, any candidates flagged `requires_human_review` trigger a
/// notification to the Data Owner registered for that entity type, so they
/// can approve or reject before a merge is allowed.
pub async fn run(task_queue: Arc<TaskQueue>, state: Arc<AppState>) {
    info!("entity_match worker started");
    loop {
        match task_queue.dequeue(task_types::ENTITY_MATCH).await {
            Ok(Some(task)) => {
                if let Err(e) = process(&state, &task).await {
                    warn!(
                        error       = %e,
                        task_id     = %task.task_id,
                        entity_id   = %task.payload.get("entity_id").and_then(|v| v.as_str()).unwrap_or("?"),
                        "entity match task failed"
                    );
                }
            }
            Ok(None) => {
                tokio::time::sleep(Duration::from_millis(500)).await;
            }
            Err(e) => {
                warn!(error = %e, "entity.match: dequeue failed; retrying in 2s");
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        }
    }
}

/// Look up per-tenant blocking rules from the DB; fall back to the
/// hardcoded defaults when no row has been configured yet.
async fn resolve_blocking_rules(
    state: &Arc<AppState>,
    tenant_id: Uuid,
    entity_type: &str,
) -> Vec<String> {
    let result = sqlx::query_scalar::<_, serde_json::Value>(
        "SELECT rules FROM core_mdm.entity_type_blocking_rules \
         WHERE tenant_id = $1 AND entity_type_code = $2",
    )
    .bind(tenant_id)
    .bind(entity_type)
    .fetch_optional(&state.db)
    .await;

    match result {
        Ok(Some(v)) => {
            if let Ok(rules) = serde_json::from_value::<Vec<String>>(v) {
                if !rules.is_empty() {
                    return rules;
                }
            }
        }
        Err(e) => {
            tracing::warn!(error=%e, "failed to load blocking rules from DB; using defaults");
        }
        _ => {}
    }

    blocking_rules_for(entity_type)
}

/// Return the appropriate blocking rules for a given entity type.
///
/// Rules are "strategy:field" or bare "strategy" tokens consumed by
/// `CandidateGenerator::generate_candidates`.  An empty vec falls back to all
/// strategies with their built-in default field lists (safe for unknown types).
fn blocking_rules_for(entity_type: &str) -> Vec<String> {
    match entity_type {
        "customer" | "person" | "individual" | "contact" => vec![
            "exact:email".into(),
            "exact:phone".into(),
            "phonetic:legal_name".into(),
            "phonetic:full_name".into(),
            "canopy:legal_name".into(),
            "canopy:full_name".into(),
            "canopy:first_name".into(),
            "canopy:last_name".into(),
            "vector".into(),
        ],
        "vendor" | "supplier" | "partner" => vec![
            "exact:tax_id".into(),
            "exact:email".into(),
            "exact:vendor_id".into(),
            "phonetic:legal_name".into(),
            "phonetic:company_name".into(),
            "canopy:legal_name".into(),
            "canopy:company_name".into(),
            "vector".into(),
        ],
        "employee" | "staff" => vec![
            "exact:email".into(),
            "phonetic:full_name".into(),
            "canopy:first_name".into(),
            "canopy:last_name".into(),
            "vector".into(),
        ],
        "company" | "organization" | "account" => vec![
            "exact:tax_id".into(),
            "exact:customer_id".into(),
            "phonetic:legal_name".into(),
            "phonetic:company_name".into(),
            "canopy:legal_name".into(),
            "canopy:company_name".into(),
            "vector".into(),
        ],
        // Unknown entity type: empty → all strategies run with default fields.
        _ => vec![],
    }
}

async fn process(state: &Arc<AppState>, task: &azile_redis::queue::Task) -> anyhow::Result<()> {
    let entity_id = task.payload
        .get("entity_id")
        .and_then(|v| v.as_str())
        .and_then(|s| Uuid::parse_str(s).ok())
        .ok_or_else(|| anyhow::anyhow!("missing entity_id"))?;

    let tenant_id = task.payload
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .and_then(|s| Uuid::parse_str(s).ok())
        .ok_or_else(|| anyhow::anyhow!("missing tenant_id"))?;

    let entity = match state.entity_service.get_entity(tenant_id, entity_id).await? {
        Some(e) => e,
        None => {
            warn!(entity_id=%entity_id, "entity not found for match task — skipping");
            return Ok(());
        }
    };

    let entity_type = format!("{:?}", entity.entity_type).to_lowercase();

    info!(entity_id=%entity_id, entity_type=%entity_type, "running entity match");

    let response = state.matching_service.execute_matching(MatchRequest {
        request_id:             Uuid::new_v4(),
        tenant_id,
        correlation_id:         None,
        entity_type:            entity_type.clone(),
        entity,
        threshold:              None,
        blocking_rules:         resolve_blocking_rules(&state, tenant_id, &entity_type).await,
        strategy:               MatchStrategy::Hybrid,
        ai_assisted:            true,
        explainability_enabled: false,
        semantic_matching:      true,
        graph_matching:         false,
        max_candidates:         10,
        metadata:               Default::default(),
    }).await?;

    let review_count = response.matches.iter().filter(|c| c.requires_human_review).count();

    info!(
        entity_id   = %entity_id,
        total       = response.matches.len(),
        review      = review_count,
        "match complete"
    );

    if review_count == 0 {
        return Ok(());
    }

    // Look up the Data Owner for this entity type and notify them.
    let owner_id: Option<Uuid> = sqlx::query_scalar(
        "SELECT identity_id \
         FROM   core_mdm.entity_type_assignments \
         WHERE  tenant_id = $1 \
           AND  entity_type_code = $2 \
           AND  assignment_type  = 'owner'",
    )
    .bind(tenant_id)
    .bind(&entity_type)
    .fetch_optional(&state.db)
    .await?;

    if let Some(owner_id) = owner_id {
        let ns = Arc::clone(&state.notification_service);
        let et = entity_type.clone();
        tokio::spawn(async move {
            let plural = if review_count == 1 { "" } else { "es" };
            ns.notify(
                tenant_id,
                Some(owner_id),
                "match.pending_owner_review",
                &format!("{} {} match{} awaiting your approval", review_count, et, plural),
                &format!(
                    "{} {} record{} matched and require{} Data Owner approval before \
                     a merge can proceed. Please review the match queue.",
                    review_count,
                    et,
                    if review_count == 1 { "" } else { "s" },
                    if review_count == 1 { "s" } else { "" },
                ),
                "info",
                serde_json::json!({
                    "entity_id":   entity_id,
                    "entity_type": et,
                    "review_count": review_count,
                }),
            )
            .await
            .ok();
        });
    }

    Ok(())
}
