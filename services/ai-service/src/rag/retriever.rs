use anyhow::Result;
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row};
use std::collections::BTreeMap;
use tracing::instrument;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RetrievedDoc {
    pub doc_id:   Uuid,
    pub doc_type: String,
    pub title:    String,
    pub content:  String,
    pub score:    f32,
}

pub struct RagRetriever {
    pool:              PgPool,
    top_k:             usize,
    min_score:         f32,
    max_doc_chars:     usize,
    max_context_chars: usize,
}

impl RagRetriever {
    pub fn new(pool: PgPool, top_k: usize, min_score: f32, max_doc_chars: usize, max_context_chars: usize) -> Self {
        Self { pool, top_k, min_score, max_doc_chars, max_context_chars }
    }

    #[instrument(skip(self, query_embedding))]
    pub async fn retrieve(
        &self,
        tenant_id:       Uuid,
        query_embedding: &[f32],
        doc_type_filter: Option<&str>,
    ) -> Result<Vec<RetrievedDoc>> {
        let embedding_literal = format!(
            "[{}]",
            query_embedding.iter().map(|f| f.to_string()).collect::<Vec<_>>().join(",")
        );

        let sql = if doc_type_filter.is_some() {
            format!(
                r#"
                SELECT doc_id, doc_type, title, content,
                       (1 - (embedding <=> '{}'::vector))::FLOAT4 AS score
                FROM ai.rag_documents
                WHERE tenant_id = $1
                  AND doc_type  = $2
                  AND embedding IS NOT NULL
                ORDER BY embedding <=> '{}'::vector
                LIMIT {}
                "#,
                embedding_literal, embedding_literal, self.top_k
            )
        } else {
            format!(
                r#"
                SELECT doc_id, doc_type, title, content,
                       (1 - (embedding <=> '{}'::vector))::FLOAT4 AS score
                FROM ai.rag_documents
                WHERE tenant_id = $1
                  AND embedding IS NOT NULL
                ORDER BY embedding <=> '{}'::vector
                LIMIT {}
                "#,
                embedding_literal, embedding_literal, self.top_k
            )
        };

        let min_score = self.min_score;
        let rows: Vec<_> = if let Some(dtype) = doc_type_filter {
            sqlx::query(&sql)
                .bind(tenant_id)
                .bind(dtype)
                .fetch_all(&self.pool)
                .await?
        } else {
            sqlx::query(&sql)
                .bind(tenant_id)
                .fetch_all(&self.pool)
                .await?
        };

        let docs = rows
            .into_iter()
            .filter_map(|r| {
                let score: f32 = r.try_get("score").unwrap_or(0.0);
                if score < min_score { return None; }
                Some(RetrievedDoc {
                    doc_id:   r.try_get("doc_id").ok()?,
                    doc_type: r.try_get("doc_type").unwrap_or_default(),
                    title:    r.try_get("title").unwrap_or_default(),
                    content:  r.try_get("content").unwrap_or_default(),
                    score,
                })
            })
            .collect();

        Ok(docs)
    }

    /// Query live entity counts from the database grouped by type and status.
    ///
    /// Returns a human-readable summary string included in every copilot prompt
    /// so the LLM can answer questions like "how many entities are defined" without
    /// needing those facts to be pre-indexed as documents.
    pub async fn fetch_live_stats(&self, tenant_id: Uuid) -> String {
        let result = sqlx::query(
            r#"
            SELECT entity_type,
                   status,
                   COUNT(*)::BIGINT                       AS cnt,
                   ROUND(AVG(trust_score)::NUMERIC, 2)    AS avg_trust
            FROM   core_mdm.entities
            WHERE  tenant_id = $1
              AND  valid_to  = 'infinity'
            GROUP  BY entity_type, status
            ORDER  BY entity_type, status
            "#,
        )
        .bind(tenant_id)
        .fetch_all(&self.pool)
        .await;

        let rows = match result {
            Err(e) => {
                tracing::warn!(error=%e, "live stats query failed");
                return String::new();
            }
            Ok(r) if r.is_empty() => return "No entities are currently stored in the system.".to_string(),
            Ok(r) => r,
        };

        // Group by entity_type, accumulate status breakdowns
        let mut by_type: BTreeMap<String, Vec<(String, i64)>> = BTreeMap::new();
        let mut grand_total: i64 = 0;

        for row in &rows {
            let etype:      String = row.try_get("entity_type").unwrap_or_default();
            let status:     String = row.try_get("status").unwrap_or_default();
            let cnt:        i64    = row.try_get("cnt").unwrap_or(0);
            grand_total += cnt;
            by_type.entry(etype).or_default().push((status, cnt));
        }

        let mut lines = Vec::with_capacity(by_type.len() + 2);
        lines.push(format!("Total entities in system: {}", grand_total));
        for (etype, statuses) in &by_type {
            let type_total: i64 = statuses.iter().map(|(_, c)| c).sum();
            let breakdown: Vec<String> = statuses
                .iter()
                .map(|(s, c)| format!("{} {}", c, s))
                .collect();
            lines.push(format!(
                "- {} entities: {} total ({})",
                etype,
                type_total,
                breakdown.join(", ")
            ));
        }

        lines.join("\n")
    }

    pub fn format_context(&self, docs: &[RetrievedDoc]) -> String {
        if docs.is_empty() {
            return "No relevant context found.".to_string();
        }

        let mut total_chars = 0usize;
        let mut parts = Vec::with_capacity(docs.len());

        for (i, doc) in docs.iter().enumerate() {
            if total_chars >= self.max_context_chars {
                break;
            }
            // Truncate per-doc content to prevent a single large document from
            // consuming the entire context window.
            let content: &str = if doc.content.len() > self.max_doc_chars {
                &doc.content[..self.max_doc_chars]
            } else {
                &doc.content
            };
            let header  = format!("[{}] {} ({})\n", i + 1, doc.title, doc.doc_type);
            let section = format!("{}{}", header, content);
            let remaining = self.max_context_chars.saturating_sub(total_chars);
            let section = if section.len() > remaining { &section[..remaining] } else { &section };
            total_chars += section.len();
            parts.push(section.to_owned());
        }

        parts.join("\n\n---\n\n")
    }

    pub async fn index_document(
        &self,
        tenant_id: Uuid,
        doc_type:  &str,
        title:     &str,
        content:   &str,
        embedding: &[f32],
    ) -> Result<Uuid> {
        let embedding_literal = format!(
            "[{}]",
            embedding.iter().map(|f| f.to_string()).collect::<Vec<_>>().join(",")
        );
        let doc_id = Uuid::new_v4();
        let sql = format!(
            r#"
            INSERT INTO ai.rag_documents (doc_id, tenant_id, doc_type, title, content, embedding)
            VALUES ($1, $2, $3, $4, $5, '{}'::vector)
            ON CONFLICT (doc_id) DO UPDATE
                SET content = EXCLUDED.content,
                    embedding = EXCLUDED.embedding,
                    title = EXCLUDED.title
            "#,
            embedding_literal
        );
        sqlx::query(&sql)
            .bind(doc_id)
            .bind(tenant_id)
            .bind(doc_type)
            .bind(title)
            .bind(content)
            .execute(&self.pool)
            .await?;
        Ok(doc_id)
    }
}
