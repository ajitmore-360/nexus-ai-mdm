use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Clone)]
pub struct TaskService {
    db: PgPool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CreateTaskInput {
    pub title:       String,
    pub description: Option<String>,
    pub task_type:   Option<String>,
    pub priority:    Option<i16>,
    pub entity_id:   Option<Uuid>,
    pub entity_type: Option<String>,
    pub assignee_id: Option<Uuid>,
    pub assignee_name: Option<String>,
    pub due_at:      Option<chrono::DateTime<chrono::Utc>>,
    pub metadata:    Option<Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UpdateTaskInput {
    pub status:          Option<String>,
    pub assignee_id:     Option<Uuid>,
    pub assignee_name:   Option<String>,
    pub priority:        Option<i16>,
    pub due_at:          Option<chrono::DateTime<chrono::Utc>>,
    pub resolution_note: Option<String>,
}

impl TaskService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    pub async fn create_task(
        &self,
        tenant_id:    Uuid,
        assigned_by:  Uuid,
        input:        CreateTaskInput,
    ) -> Result<Uuid, sqlx::Error> {
        let task_type = input.task_type.unwrap_or_else(|| "Manual".to_string());
        let priority  = input.priority.unwrap_or(2);
        let metadata  = input.metadata.unwrap_or(json!({}));

        let id: Uuid = sqlx::query_scalar(
            r#"
            INSERT INTO core_mdm.tasks
                (tenant_id, title, description, task_type, priority,
                 entity_id, entity_type,
                 assignee_id, assignee_name, assigned_by, assigned_at,
                 due_at, metadata)
            VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,
                    CASE WHEN $8 IS NOT NULL THEN NOW() END,
                    $11,$12)
            RETURNING id
            "#,
        )
        .bind(tenant_id)
        .bind(&input.title)
        .bind(&input.description)
        .bind(&task_type)
        .bind(priority)
        .bind(input.entity_id)
        .bind(&input.entity_type)
        .bind(input.assignee_id)
        .bind(&input.assignee_name)
        .bind(assigned_by)
        .bind(input.due_at)
        .bind(&metadata)
        .fetch_one(&self.db)
        .await?;

        Ok(id)
    }

    pub async fn list_tasks(
        &self,
        tenant_id:   Uuid,
        assignee_id: Option<Uuid>,
        status:      Option<&str>,
        entity_id:   Option<Uuid>,
        limit:       i64,
        offset:      i64,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT id, title, description, task_type, status, priority,
                   entity_id, entity_type,
                   assignee_id, assignee_name, assigned_by, assigned_at,
                   due_at, sla_breached, escalated_to,
                   completed_by, completed_at, resolution_note,
                   metadata, created_at, updated_at
            FROM core_mdm.tasks
            WHERE tenant_id = $1
              AND ($2::uuid IS NULL OR assignee_id = $2)
              AND ($3::text IS NULL OR status = $3)
              AND ($4::uuid IS NULL OR entity_id = $4)
            ORDER BY priority DESC, due_at ASC NULLS LAST, created_at DESC
            LIMIT $5 OFFSET $6
            "#,
        )
        .bind(tenant_id)
        .bind(assignee_id)
        .bind(status)
        .bind(entity_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| json!({
            "id":              r.get::<Uuid, _>("id"),
            "title":           r.get::<String, _>("title"),
            "description":     r.get::<Option<String>, _>("description"),
            "task_type":       r.get::<String, _>("task_type"),
            "status":          r.get::<String, _>("status"),
            "priority":        r.get::<i16, _>("priority"),
            "entity_id":       r.get::<Option<Uuid>, _>("entity_id"),
            "entity_type":     r.get::<Option<String>, _>("entity_type"),
            "assignee_id":     r.get::<Option<Uuid>, _>("assignee_id"),
            "assignee_name":   r.get::<Option<String>, _>("assignee_name"),
            "due_at":          r.get::<Option<chrono::DateTime<chrono::Utc>>, _>("due_at").map(|d| d.to_rfc3339()),
            "sla_breached":    r.get::<bool, _>("sla_breached"),
            "completed_at":    r.get::<Option<chrono::DateTime<chrono::Utc>>, _>("completed_at").map(|d| d.to_rfc3339()),
            "resolution_note": r.get::<Option<String>, _>("resolution_note"),
            "created_at":      r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
        })).collect())
    }

    pub async fn update_task(
        &self,
        tenant_id: Uuid,
        task_id:   Uuid,
        actor_id:  Uuid,
        input:     UpdateTaskInput,
    ) -> Result<bool, sqlx::Error> {
        let completed_at = if input.status.as_deref() == Some("Completed") {
            Some(chrono::Utc::now())
        } else { None };
        let completed_by = if input.status.as_deref() == Some("Completed") {
            Some(actor_id)
        } else { None };

        let result = sqlx::query(
            r#"
            UPDATE core_mdm.tasks SET
                status          = COALESCE($3, status),
                assignee_id     = COALESCE($4, assignee_id),
                assignee_name   = COALESCE($5, assignee_name),
                priority        = COALESCE($6, priority),
                due_at          = COALESCE($7, due_at),
                resolution_note = COALESCE($8, resolution_note),
                completed_at    = COALESCE($9, completed_at),
                completed_by    = COALESCE($10, completed_by),
                updated_at      = NOW()
            WHERE id = $1 AND tenant_id = $2
            "#,
        )
        .bind(task_id)
        .bind(tenant_id)
        .bind(&input.status)
        .bind(input.assignee_id)
        .bind(&input.assignee_name)
        .bind(input.priority)
        .bind(input.due_at)
        .bind(&input.resolution_note)
        .bind(completed_at)
        .bind(completed_by)
        .execute(&self.db)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    /// Check for SLA breaches and mark tasks as sla_breached=true.
    /// Called by a background worker / scheduler.
    pub async fn check_sla_breaches(&self, tenant_id: Uuid) -> Result<u64, sqlx::Error> {
        let result = sqlx::query(
            r#"
            UPDATE core_mdm.tasks
            SET sla_breached = TRUE, updated_at = NOW()
            WHERE tenant_id = $1
              AND status NOT IN ('Completed', 'Cancelled')
              AND due_at < NOW()
              AND sla_breached = FALSE
            "#,
        )
        .bind(tenant_id)
        .execute(&self.db)
        .await?;

        Ok(result.rows_affected())
    }
}
