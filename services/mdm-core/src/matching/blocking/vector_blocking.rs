use std::collections::HashSet;

use async_trait::async_trait;
use sqlx::{PgPool, Row};
use tracing::{debug, warn};
use uuid::Uuid;

use contracts::mdm::entity::CanonicalEntity;

use crate::matching::blocking::strategy::BlockingStrategy;

/// Maximum number of ANN neighbours to return per entity.
const ANN_LIMIT: i64 = 200;

/// pgvector-based semantic blocking.
///
/// Performs an approximate nearest-neighbour search against `ai.entity_embeddings`
/// to surface semantically similar candidates that exact or phonetic blocking miss
/// (e.g. "IBM" vs "International Business Machines").
///
/// Falls back gracefully (empty set) when the source entity has no stored embedding
/// yet — phonetic + canopy blocking still run and cover those cases.
pub struct VectorBlocker {
    pool: PgPool,
}

impl VectorBlocker {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl BlockingStrategy for VectorBlocker {
    fn name(&self) -> &'static str {
        "vector"
    }

    async fn find_candidates(
        &self,
        tenant_id: Uuid,
        entity:    &CanonicalEntity,
        _fields:   Option<&[String]>,
    ) -> anyhow::Result<HashSet<Uuid>> {
        // Query ANN neighbours using the source entity's stored embedding.
        // The <=> operator is cosine distance (pgvector). IVFFlat index makes
        // this sub-millisecond at scale.
        let rows = sqlx::query(
            r#"
            SELECT   neighbour.entity_id
            FROM     ai.entity_embeddings AS source
            JOIN     ai.entity_embeddings AS neighbour
                     ON  neighbour.tenant_id != source.tenant_id
                     OR  neighbour.entity_id != source.entity_id
            WHERE    source.entity_id = $1
              AND    source.tenant_id = $2
              AND    neighbour.tenant_id = $2
            ORDER BY source.embedding <=> neighbour.embedding
            LIMIT    $3
            "#,
        )
        .bind(entity.entity_id)
        .bind(tenant_id)
        .bind(ANN_LIMIT)
        .fetch_all(&self.pool)
        .await;

        match rows {
            Ok(rows) => {
                let ids: HashSet<Uuid> = rows
                    .into_iter()
                    .filter_map(|r| r.try_get::<Uuid, _>("entity_id").ok())
                    .collect();
                debug!(
                    entity_id = %entity.entity_id,
                    neighbours = ids.len(),
                    "vector blocking completed"
                );
                Ok(ids)
            }
            Err(sqlx::Error::RowNotFound) => {
                // Source entity has no embedding yet — non-fatal.
                debug!(entity_id=%entity.entity_id, "vector blocking skipped: no embedding stored");
                Ok(HashSet::new())
            }
            Err(e) => {
                warn!(entity_id=%entity.entity_id, error=%e, "vector blocking query failed");
                Ok(HashSet::new())
            }
        }
    }
}
