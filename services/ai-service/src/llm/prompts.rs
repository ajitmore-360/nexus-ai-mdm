use serde_json::Value;

/// Structured prompt templates for every LLM task in the system.
pub struct Prompts;

impl Prompts {
    // =========================================================================
    // MATCH EXPLANATION
    // =========================================================================

    pub fn explain_match(
        source_attrs:    &Value,
        candidate_attrs: &Value,
        score:           f32,
        field_results:   &Value,
    ) -> String {
        format!(
            r#"You are a Master Data Management expert. Explain in 2-3 clear sentences why these two records were matched.

SOURCE RECORD:
{source}

CANDIDATE RECORD:
{candidate}

MATCH SCORE: {score:.1}%
FIELD-LEVEL RESULTS:
{fields}

Provide a concise, factual explanation a business user can understand.
Focus on which specific fields matched or conflicted.
Do NOT use technical jargon. Do NOT exceed 3 sentences."#,
            source   = serde_json::to_string_pretty(source_attrs).unwrap_or_default(),
            candidate = serde_json::to_string_pretty(candidate_attrs).unwrap_or_default(),
            score    = score * 100.0,
            fields   = serde_json::to_string_pretty(field_results).unwrap_or_default(),
        )
    }

    // =========================================================================
    // SEMANTIC MATCH RESOLUTION  (grey-zone 0.75–0.95)
    // =========================================================================

    pub fn resolve_ambiguous_match(
        source_attrs:    &Value,
        candidate_attrs: &Value,
        score:           f32,
        context:         &str,
    ) -> String {
        format!(
            r#"You are an expert data steward for a {context} dataset.
Two records have been flagged for review with a match score of {score:.1}%.
Decide: are these the SAME real-world entity, or are they DIFFERENT entities?

RECORD A:
{source}

RECORD B:
{candidate}

Rules:
- If critical identifiers (Tax ID, SSN, DUNS, email domain) are identical → SAME
- If names differ only by abbreviation, suffix, or punctuation → likely SAME
- If addresses or DOBs conflict significantly → likely DIFFERENT
- Consider common data entry errors and abbreviations

Respond with EXACTLY this JSON format (no extra text):
{{"decision":"match"|"no_match","confidence":0.0-1.0,"reasoning":"one sentence"}}"#,
            context   = context,
            score     = score * 100.0,
            source    = serde_json::to_string_pretty(source_attrs).unwrap_or_default(),
            candidate = serde_json::to_string_pretty(candidate_attrs).unwrap_or_default(),
        )
    }

    // =========================================================================
    // SURVIVORSHIP RULE SUGGESTION
    // =========================================================================

    pub fn suggest_survivorship_rules(
        field_name:       &str,
        entity_type:      &str,
        merge_history:    &Value,
        source_trust_map: &Value,
    ) -> String {
        format!(
            r#"You are a Master Data Management architect. Suggest the optimal survivorship rule for field "{field}" in entity type "{entity_type}".

HISTORICAL MERGE DECISIONS (last 500 merges):
{history}

SOURCE SYSTEM TRUST SCORES:
{trust}

Analyse which source system's value was chosen most often and why.
Respond with EXACTLY this JSON (no extra text):
{{
  "strategy": "TrustedSource"|"MostRecent"|"LongestValue"|"HighestConfidence"|"HybridWeighted",
  "primary_source": "source_system_name or null",
  "reasoning": "one concise sentence",
  "confidence": 0.0-1.0
}}"#,
            field       = field_name,
            entity_type = entity_type,
            history     = serde_json::to_string_pretty(merge_history).unwrap_or_default(),
            trust       = serde_json::to_string_pretty(source_trust_map).unwrap_or_default(),
        )
    }

    // =========================================================================
    // AI COPILOT (RAG-augmented)
    // =========================================================================

    pub fn copilot_rag(
        user_prompt:  &str,
        context_docs: &str,
        tenant_name:  &str,
    ) -> String {
        format!(
            r#"You are Nexus AI Copilot, an intelligent assistant for {tenant} Master Data Management.
Use ONLY the context below to answer the user's question.
If the context doesn't contain enough information, say so clearly.
Keep answers concise and actionable.

CONTEXT FROM KNOWLEDGE BASE:
{context}

USER QUESTION:
{prompt}

Answer:"#,
            tenant  = tenant_name,
            context = context_docs,
            prompt  = user_prompt,
        )
    }

    // =========================================================================
    // DATA QUALITY ANOMALY DESCRIPTION
    // =========================================================================

    #[allow(dead_code)]   // Used by anomaly detection feature — wired in future sprint
    pub fn describe_anomaly(
        field_name:  &str,
        entity_type: &str,
        anomaly_stats: &Value,
    ) -> String {
        format!(
            r#"You are a data quality analyst. Describe this data quality anomaly in plain business English (2 sentences max).

FIELD: {field}
ENTITY TYPE: {entity_type}
ANOMALY STATISTICS:
{stats}

Be specific about the impact and urgency. Do not use technical jargon."#,
            field       = field_name,
            entity_type = entity_type,
            stats       = serde_json::to_string_pretty(anomaly_stats).unwrap_or_default(),
        )
    }

    // =========================================================================
    // GOLDEN RECORD SUMMARY
    // =========================================================================

    #[allow(dead_code)]   // Used when golden records are exposed via MCP copilot
    pub fn summarise_golden_record(attributes: &Value, source_count: usize) -> String {
        format!(
            r#"Summarise this master data record in one sentence for a business user.
Include the entity name, key identifiers, and number of source systems ({count} sources).

ATTRIBUTES:
{attrs}

Summary (one sentence only):"#,
            count = source_count,
            attrs = serde_json::to_string_pretty(attributes).unwrap_or_default(),
        )
    }
}
