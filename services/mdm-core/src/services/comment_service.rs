use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Clone)]
pub struct CommentService {
    db: PgPool,
}

impl CommentService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    pub async fn list_comments(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
        limit:     i64,
        offset:    i64,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT id, entity_id, author_id, author_name, content, is_edited, created_at, updated_at
            FROM core_mdm.entity_comments
            WHERE tenant_id = $1 AND entity_id = $2
            ORDER BY created_at ASC
            LIMIT $3 OFFSET $4
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| json!({
            "id":          r.get::<Uuid, _>("id"),
            "entity_id":   r.get::<Uuid, _>("entity_id"),
            "author_id":   r.get::<Uuid, _>("author_id"),
            "author_name": r.get::<String, _>("author_name"),
            "content":     r.get::<String, _>("content"),
            "is_edited":   r.get::<bool, _>("is_edited"),
            "created_at":  r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
            "updated_at":  r.get::<chrono::DateTime<chrono::Utc>, _>("updated_at").to_rfc3339(),
        })).collect())
    }

    pub async fn add_comment(
        &self,
        tenant_id:   Uuid,
        entity_id:   Uuid,
        author_id:   Uuid,
        author_name: &str,
        content:     &str,
    ) -> Result<Uuid, sqlx::Error> {
        let mut tx = self.db.begin().await?;

        sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
            .bind(tenant_id.to_string())
            .execute(&mut *tx)
            .await?;

        let id: Uuid = sqlx::query_scalar(
            r#"
            INSERT INTO core_mdm.entity_comments (tenant_id, entity_id, author_id, author_name, content)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING id
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(author_id)
        .bind(author_name)
        .bind(content)
        .fetch_one(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(id)
    }

    pub async fn edit_comment(
        &self,
        tenant_id:  Uuid,
        comment_id: Uuid,
        author_id:  Uuid,
        content:    &str,
    ) -> Result<bool, sqlx::Error> {
        let n = sqlx::query_scalar::<_, i64>(
            r#"
            UPDATE core_mdm.entity_comments
            SET content = $1, is_edited = true, updated_at = NOW()
            WHERE id = $2 AND tenant_id = $3 AND author_id = $4
            RETURNING 1
            "#,
        )
        .bind(content)
        .bind(comment_id)
        .bind(tenant_id)
        .bind(author_id)
        .fetch_optional(&self.db)
        .await?;
        Ok(n.is_some())
    }

    pub async fn delete_comment(
        &self,
        tenant_id:  Uuid,
        comment_id: Uuid,
        author_id:  Uuid,
        is_admin:   bool,
    ) -> Result<bool, sqlx::Error> {
        let n = sqlx::query_scalar::<_, i64>(
            r#"
            DELETE FROM core_mdm.entity_comments
            WHERE id = $1 AND tenant_id = $2 AND (author_id = $3 OR $4 = true)
            RETURNING 1
            "#,
        )
        .bind(comment_id)
        .bind(tenant_id)
        .bind(author_id)
        .bind(is_admin)
        .fetch_optional(&self.db)
        .await?;
        Ok(n.is_some())
    }

    pub async fn count_comments(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
    ) -> Result<i64, sqlx::Error> {
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM core_mdm.entity_comments WHERE tenant_id=$1 AND entity_id=$2",
        )
        .bind(tenant_id)
        .bind(entity_id)
        .fetch_one(&self.db)
        .await?;
        Ok(count)
    }
}
