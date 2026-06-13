use anyhow::Result;
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row};
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
    pool:      PgPool,
    top_k:     usize,
    min_score: f32,
}

impl RagRetriever {
    pub fn new(pool: PgPool, top_k: usize, min_score: f32) -> Self {
        Self { pool, top_k, min_score }
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

    pub fn format_context(docs: &[RetrievedDoc]) -> String {
        if docs.is_empty() {
            return "No relevant context found.".to_string();
        }
        docs.iter()
            .enumerate()
            .map(|(i, doc)| format!("[{}] {} ({})\n{}", i + 1, doc.title, doc.doc_type, doc.content))
            .collect::<Vec<_>>()
            .join("\n\n---\n\n")
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
