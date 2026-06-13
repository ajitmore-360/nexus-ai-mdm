use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{PgPool, Row};
use tracing::instrument;
use uuid::Uuid;

// ─────────────────────────────────────────────────────────────────────────────
// REQUEST / RESPONSE TYPES
// ─────────────────────────────────────────────────────────────────────────────

/// A full search request supporting both text and vector queries.
#[derive(Debug, Deserialize)]
pub struct SearchRequest {
    pub tenant_id:   Uuid,
    /// Free-text query string.
    pub query:       String,
    /// Optional entity type filter.
    pub entity_type: Option<String>,
    /// Optional status filter.
    pub status:      Option<String>,
    /// Pre-computed query embedding from ai-service (for vector search lane).
    pub embedding:   Option<Vec<f32>>,
    pub limit:       Option<i64>,
    pub offset:      Option<i64>,
    /// Weight of full-text score vs vector score (0.0 = pure FTS, 1.0 = pure vector).
    pub vector_weight: Option<f32>,
}

#[derive(Debug, Serialize)]
pub struct SearchResult {
    pub hits:         Vec<SearchHit>,
    pub total:        i64,
    pub query:        String,
    pub search_mode:  SearchMode,
    pub facets:       Facets,
}

#[derive(Debug, Serialize)]
pub struct SearchHit {
    pub entity_id:    Uuid,
    pub entity_type:  String,
    pub status:       String,
    pub attributes:   Value,
    pub trust_score:  f32,
    pub fts_score:    f32,
    pub vector_score: f32,
    pub final_score:  f32,
    pub highlights:   Vec<String>,
    pub source_system: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SearchMode {
    FullTextOnly,
    #[allow(dead_code)]
    VectorOnly,
    Hybrid,
}

#[derive(Debug, Serialize)]
pub struct Facets {
    pub entity_types: Vec<FacetBucket>,
    pub statuses:     Vec<FacetBucket>,
    pub sources:      Vec<FacetBucket>,
}

#[derive(Debug, Serialize)]
pub struct FacetBucket {
    pub value: String,
    pub count: i64,
}

// ─────────────────────────────────────────────────────────────────────────────
// SEARCH ENGINE
// ─────────────────────────────────────────────────────────────────────────────

pub struct SearchEngine {
    pool: PgPool,
}

impl SearchEngine {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Execute a hybrid search combining PostgreSQL FTS and pgvector ANN.
    ///
    /// When an embedding is provided the results are blended using `vector_weight`
    /// (default 0.30 = 70% FTS, 30% vector).  Without an embedding only FTS is used.
    #[instrument(skip(self, request), fields(tenant_id=%request.tenant_id))]
    pub async fn search(&self, request: &SearchRequest) -> Result<SearchResult> {
        let limit        = request.limit.unwrap_or(20).min(200);
        let offset       = request.offset.unwrap_or(0);
        let vector_weight = request.vector_weight.unwrap_or(0.30).clamp(0.0, 1.0);

        let (hits, mode) = if let Some(emb) = &request.embedding {
            self.hybrid_search(request, emb, vector_weight, limit, offset).await?
        } else {
            self.fts_search(request, limit, offset).await?
        };

        let total  = self.count(request).await?;
        let facets = self.facets(request.tenant_id, &request.entity_type).await?;

        Ok(SearchResult {
            hits,
            total,
            query: request.query.clone(),
            search_mode: mode,
            facets,
        })
    }

    // ── Full-text search ─────────────────────────────────────────────────────

    async fn fts_search(
        &self,
        req:    &SearchRequest,
        limit:  i64,
        offset: i64,
    ) -> Result<(Vec<SearchHit>, SearchMode)> {
        let base_sql = r#"
            SELECT
                e.entity_id,
                e.entity_type,
                e.status,
                e.metadata AS attributes,
                e.trust_score,
                GREATEST(
                    ts_rank(to_tsvector('english', e.metadata::text), plainto_tsquery('english', $3)),
                    COALESCE((
                        SELECT MAX(ts_rank(to_tsvector('english', a.attribute_value::text), plainto_tsquery('english', $3)))
                        FROM core_mdm.entity_attributes a
                        WHERE a.entity_id = e.entity_id AND a.tenant_id = e.tenant_id
                    ), 0)
                ) AS fts_rank,
                e.source_system
            FROM core_mdm.entities e
            WHERE e.tenant_id = $1
              AND e.valid_to  = 'infinity'
              AND (
                to_tsvector('english', e.metadata::text) @@ plainto_tsquery('english', $3)
                OR EXISTS (
                    SELECT 1 FROM core_mdm.entity_attributes a
                    WHERE a.entity_id = e.entity_id
                      AND a.tenant_id = e.tenant_id
                      AND to_tsvector('english', a.attribute_value::text)
                          @@ plainto_tsquery('english', $3)
                )
              )
        "#;

        let rows = if let Some(etype) = &req.entity_type {
            let sql = format!("{} AND e.entity_type = $5 ORDER BY fts_rank DESC LIMIT $4 OFFSET $6", base_sql);
            sqlx::query(&sql)
                .bind(req.tenant_id)
                .bind(req.status.as_deref())
                .bind(&req.query)
                .bind(limit)
                .bind(etype)
                .bind(offset)
                .fetch_all(&self.pool)
                .await?
        } else {
            let sql = format!("{} ORDER BY fts_rank DESC LIMIT $4 OFFSET $5", base_sql);
            sqlx::query(&sql)
                .bind(req.tenant_id)
                .bind(req.status.as_deref())
                .bind(&req.query)
                .bind(limit)
                .bind(offset)
                .fetch_all(&self.pool)
                .await?
        };

        let hits = rows.into_iter().map(|r| SearchHit {
            entity_id:    r.try_get("entity_id").unwrap_or(Uuid::nil()),
            entity_type:  r.try_get("entity_type").unwrap_or_default(),
            status:       r.try_get("status").unwrap_or_default(),
            attributes:   r.try_get::<Value, _>("attributes").unwrap_or(Value::Null),
            trust_score:  r.try_get::<f32, _>("trust_score").unwrap_or(0.0),
            fts_score:    r.try_get::<f32, _>("fts_rank").unwrap_or(0.0),
            vector_score: 0.0,
            final_score:  r.try_get::<f32, _>("fts_rank").unwrap_or(0.0),
            highlights:   vec![],
            source_system: r.try_get("source_system").ok().flatten(),
        }).collect();

        Ok((hits, SearchMode::FullTextOnly))
    }

    // ── Hybrid search ─────────────────────────────────────────────────────────

    async fn hybrid_search(
        &self,
        req:           &SearchRequest,
        embedding:     &[f32],
        vector_weight: f32,
        limit:         i64,
        offset:        i64,
    ) -> Result<(Vec<SearchHit>, SearchMode)> {
        // ── Security: validate embedding before any SQL construction ─────────
        // Ensure every component is a finite normal float so the literal
        // cannot contain unexpected characters (NaN, inf, -inf).
        // Dimensions > 4096 indicate a malformed/oversized vector.
        if embedding.is_empty() || embedding.len() > 4096 {
            anyhow::bail!("embedding dimension out of range [1, 4096]");
        }
        for &v in embedding {
            if !v.is_finite() {
                anyhow::bail!("embedding contains non-finite float value");
            }
        }
        let vector_weight = vector_weight.clamp(0.0, 1.0);

        // Build the vector literal only after validation.
        // pgvector does not yet support $n-style binding for vector literals,
        // so we must inline the value.  After validation above, the string
        // contains only ASCII digits, minus signs, dots, commas and brackets.
        let emb_literal = format!(
            "[{}]",
            embedding.iter()
                .map(|f| format!("{:.8}", f))   // fixed precision — no exponent notation
                .collect::<Vec<_>>()
                .join(",")
        );

        let fts_w = (1.0_f64 - vector_weight as f64).clamp(0.0, 1.0);
        let vec_w = vector_weight as f64;

        // NOTE: Only the embedding literal is inlined — all other user inputs
        // use $n parameterised binding as usual.
        let sql = format!(
            r#"
            SELECT
                e.entity_id,
                e.entity_type,
                e.status,
                e.metadata AS attributes,
                e.trust_score,
                e.source_system,
                ts_rank(to_tsvector('english', e.metadata::text), plainto_tsquery('english', $3)) AS fts_score,
                (1 - (ae.embedding <=> '{emb}'::vector))::FLOAT4 AS vector_score,
                ({fts_w} * ts_rank(to_tsvector('english', e.metadata::text), plainto_tsquery('english', $3))
                + {vec_w} * (1 - (ae.embedding <=> '{emb}'::vector))::FLOAT4) AS final_score
            FROM core_mdm.entities e
            JOIN ai.entity_embeddings ae
              ON ae.entity_id = e.entity_id AND ae.tenant_id = e.tenant_id
            WHERE e.tenant_id = $1
              AND e.valid_to  = 'infinity'
            ORDER BY final_score DESC
            LIMIT $4 OFFSET $5
            "#,
            emb   = emb_literal,
            fts_w = fts_w,
            vec_w = vec_w,
        );

        let rows = sqlx::query(&sql)
            .bind(req.tenant_id)
            .bind(req.status.as_deref())
            .bind(&req.query)
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.pool)
            .await
            .unwrap_or_default(); // fall back to empty if embeddings table is empty

        let hits = rows.into_iter().map(|r| SearchHit {
            entity_id:    r.try_get("entity_id").unwrap_or(Uuid::nil()),
            entity_type:  r.try_get("entity_type").unwrap_or_default(),
            status:       r.try_get("status").unwrap_or_default(),
            attributes:   r.try_get::<Value, _>("attributes").unwrap_or(Value::Null),
            trust_score:  r.try_get::<f32, _>("trust_score").unwrap_or(0.0),
            fts_score:    r.try_get::<f32, _>("fts_score").unwrap_or(0.0),
            vector_score: r.try_get::<f32, _>("vector_score").unwrap_or(0.0),
            final_score:  r.try_get::<f32, _>("final_score").unwrap_or(0.0),
            highlights:   vec![],
            source_system: r.try_get("source_system").ok().flatten(),
        }).collect();

        Ok((hits, SearchMode::Hybrid))
    }

    // ── Total count ──────────────────────────────────────────────────────────

    async fn count(&self, req: &SearchRequest) -> Result<i64> {
        let row = sqlx::query(
            r#"
            SELECT COUNT(*)
            FROM core_mdm.entities e
            WHERE e.tenant_id = $1
              AND e.valid_to  = 'infinity'
              AND (
                to_tsvector('english', e.metadata::text) @@ plainto_tsquery('english', $2)
                OR EXISTS (
                    SELECT 1 FROM core_mdm.entity_attributes a
                    WHERE a.entity_id = e.entity_id
                      AND a.tenant_id = e.tenant_id
                      AND to_tsvector('english', a.attribute_value::text)
                          @@ plainto_tsquery('english', $2)
                )
              )
            "#,
        )
        .bind(req.tenant_id)
        .bind(&req.query)
        .fetch_one(&self.pool)
        .await?;

        Ok(row.try_get::<i64, _>(0).unwrap_or(0))
    }

    // ── Facets ────────────────────────────────────────────────────────────────

    async fn facets(&self, tenant_id: Uuid, _entity_type_filter: &Option<String>) -> Result<Facets> {
        let type_rows = sqlx::query(
            "SELECT entity_type, COUNT(*) AS cnt FROM core_mdm.entities WHERE tenant_id=$1 AND valid_to='infinity' GROUP BY entity_type ORDER BY cnt DESC LIMIT 10"
        )
        .bind(tenant_id)
        .fetch_all(&self.pool).await.unwrap_or_default();

        let status_rows = sqlx::query(
            "SELECT status, COUNT(*) AS cnt FROM core_mdm.entities WHERE tenant_id=$1 AND valid_to='infinity' GROUP BY status ORDER BY cnt DESC"
        )
        .bind(tenant_id)
        .fetch_all(&self.pool).await.unwrap_or_default();

        let source_rows = sqlx::query(
            "SELECT source_system, COUNT(*) AS cnt FROM core_mdm.entities WHERE tenant_id=$1 AND valid_to='infinity' AND source_system IS NOT NULL GROUP BY source_system ORDER BY cnt DESC LIMIT 10"
        )
        .bind(tenant_id)
        .fetch_all(&self.pool).await.unwrap_or_default();

        let to_buckets = |rows: Vec<sqlx::postgres::PgRow>| -> Vec<FacetBucket> {
            rows.into_iter().filter_map(|r| {
                let value: String = r.try_get(0).ok()?;
                let count: i64    = r.try_get(1).ok()?;
                Some(FacetBucket { value, count })
            }).collect()
        };

        Ok(Facets {
            entity_types: to_buckets(type_rows),
            statuses:     to_buckets(status_rows),
            sources:      to_buckets(source_rows),
        })
    }

    /// Autocomplete: return entity names starting with `prefix` (max 10).
    pub async fn autocomplete(&self, tenant_id: Uuid, prefix: &str) -> Result<Vec<String>> {
        let pattern = format!("{}%", prefix.to_lowercase());
        let rows = sqlx::query(
            r#"
            SELECT DISTINCT ea.attribute_value ->> 0 AS name
            FROM core_mdm.entity_attributes ea
            WHERE ea.tenant_id     = $1
              AND ea.attribute_key IN ('name', 'legal_name', 'company_name')
              AND lower(ea.attribute_value::text) LIKE $2
            LIMIT 10
            "#,
        )
        .bind(tenant_id)
        .bind(&pattern)
        .fetch_all(&self.pool)
        .await
        .unwrap_or_default();

        Ok(rows.into_iter()
            .filter_map(|r| r.try_get::<String, _>("name").ok())
            .collect())
    }
}
