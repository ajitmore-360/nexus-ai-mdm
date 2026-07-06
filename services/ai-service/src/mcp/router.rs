use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tracing::{info, instrument};
use uuid::Uuid;

use crate::anomaly::AnomalyDetector;
use crate::mcp::tools::{
    detect_anomalies::{detect_anomalies, DetectAnomaliesArgs},
    explain_match::{explain_match, ExplainMatchArgs},
    quality_report::{quality_report, QualityReportArgs},
    search_entities::{search_entities, SearchEntitiesArgs},
    suggest_rules::{suggest_survivorship_rules, SuggestRulesArgs},
};
use crate::state::AppState;

/// An inbound MCP request from the Flutter client / api-gateway.
#[derive(Debug, Deserialize)]
pub struct McpRequest {
    pub tenant_id:       Uuid,
    /// The authenticated user making this request. Injected by the gateway
    /// from the validated JWT so callers cannot self-assign an identity.
    /// Included in every tracing span for audit correlation.
    pub user_id:         Option<Uuid>,
    /// Role injected by the API gateway from JWT claims.
    /// Deserialized for completeness but the handler reads role from the
    /// x-user-role header instead (authoritative, JWT-derived).
    #[allow(dead_code)]
    pub role:            Option<String>,
    /// Explicit tool call, or None for free-form RAG Q&A.
    pub tool:            Option<String>,
    pub args:            Option<Value>,
    pub prompt:          Option<String>,
    pub correlation_id:  Option<String>,
    /// Client hint: "auto" (default) | "prose" | "table".
    pub response_format: Option<String>,
}

/// Server-resolved identity context built by the handler — never from the
/// client body directly.
#[derive(Debug)]
pub struct RoleContext {
    pub role:         String,
    pub entity_types: Vec<String>,
    pub fmt:          String, // "prose" | "table"
}

/// The response returned to the client.
#[derive(Debug, Serialize)]
pub struct McpResponse {
    pub success:        bool,
    pub tool:           Option<String>,
    pub result:         Option<Value>,
    pub answer:         Option<String>,
    pub source_docs:    Option<Vec<SourceDocSummary>>,
    pub error:          Option<String>,
    pub correlation_id: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct SourceDocSummary {
    pub title:    String,
    pub doc_type: String,
    pub score:    f32,
}

/// Routes an MCP request to the right tool or the RAG copilot pipeline.
///
/// `user_id` is captured in the tracing span so every log line emitted
/// during this request (including from called tools) is tagged with both
/// the tenant and the user — enabling audit correlation without additional
/// logging boilerplate in each tool.
#[instrument(
    skip(state),
    fields(
        tenant_id = %request.tenant_id,
        user_id   = ?request.user_id,
    )
)]
pub async fn route(state: &AppState, request: McpRequest, ctx: RoleContext) -> McpResponse {
    let cid = request.correlation_id.clone();

    match dispatch(state, &request, &ctx).await {
        Ok(response) => response,
        Err(e) => {
            tracing::error!(error=%e, "MCP dispatch failed");
            McpResponse {
                success:        false,
                tool:           request.tool,
                result:         None,
                answer:         None,
                source_docs:    None,
                error:          Some(e.to_string()),
                correlation_id: cid,
            }
        }
    }
}

async fn dispatch(state: &AppState, request: &McpRequest, ctx: &RoleContext) -> Result<McpResponse> {
    let cid = request.correlation_id.clone();

    // ── Explicit tool call ───────────────────────────────────────────────────
    if let Some(tool) = &request.tool {
        let args = request.args.clone().unwrap_or(Value::Null);
        info!(
            tool          = %tool,
            tenant_id     = %request.tenant_id,
            user_id       = ?request.user_id,
            "MCP tool invoked"
        );

        let result = match tool.as_str() {

            "search_entities" => {
                let a: SearchEntitiesArgs = serde_json::from_value(args)?;
                search_entities(&state.pool, request.tenant_id, a).await?
            }

            "explain_match" => {
                let a: ExplainMatchArgs = serde_json::from_value(args)?;
                explain_match(&state.pool, &state.semantic_matcher, request.tenant_id, a).await?
            }

            "quality_report" => {
                let a: QualityReportArgs = serde_json::from_value(args)?;
                quality_report(&state.pool, request.tenant_id, a).await?
            }

            "suggest_survivorship_rules" => {
                let a: SuggestRulesArgs = serde_json::from_value(args)?;
                suggest_survivorship_rules(&state.pool, &state.llm, request.tenant_id, a).await?
            }

            "detect_anomalies" => {
                let a: DetectAnomaliesArgs = serde_json::from_value(args)?;
                let detector = AnomalyDetector::new(state.pool.clone());
                detect_anomalies(&detector, request.tenant_id, a).await?
            }

            unknown => return Err(anyhow!("unknown MCP tool: '{}'", unknown)),
        };

        return Ok(McpResponse {
            success:        true,
            tool:           Some(tool.clone()),
            result:         Some(result),
            answer:         None,
            source_docs:    None,
            error:          None,
            correlation_id: cid,
        });
    }

    // ── Free-form copilot question (RAG) ────────────────────────────────────
    let raw_prompt = request.prompt.as_deref().unwrap_or("").trim();
    if raw_prompt.is_empty() {
        return Err(anyhow!("either 'tool' or 'prompt' must be provided"));
    }

    // Sanitize before sending to LLM — prevent prompt injection
    let prompt = crate::llm::sanitize_user_query(raw_prompt);
    if prompt.contains("redacted") {
        tracing::warn!(
            user_id   = ?request.user_id,
            tenant_id = %request.tenant_id,
            "MCP prompt injection attempt blocked"
        );
        return Ok(McpResponse {
            success:        false,
            tool:           None,
            result:         None,
            answer:         Some(
                "Your query was blocked — it contains patterns that are not permitted in the AI copilot."
                    .to_string(),
            ),
            source_docs:    None,
            error:          Some("prompt injection pattern detected".to_string()),
            correlation_id: cid,
        });
    }

    let tenant_name = state.tenant_name(request.tenant_id).await;
    let rag_answer  = state
        .rag_pipeline
        .answer(request.tenant_id, &tenant_name, &prompt, None, &ctx.role, &ctx.entity_types, &ctx.fmt)
        .await?;

    let source_docs: Vec<SourceDocSummary> = rag_answer
        .source_docs
        .iter()
        .map(|d| SourceDocSummary {
            title:    d.title.clone(),
            doc_type: d.doc_type.clone(),
            score:    d.score,
        })
        .collect();

    Ok(McpResponse {
        success:        true,
        tool:           None,
        result:         None,
        answer:         Some(rag_answer.answer),
        source_docs:    Some(source_docs),
        error:          None,
        correlation_id: cid,
    })
}
