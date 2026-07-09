use axum::http::StatusCode;
use sqlx::PgPool;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use chrono::{DateTime, Utc};

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct WorkflowDefinition {
    pub workflow_id:    Uuid,
    pub tenant_id:      Uuid,
    pub name:           String,
    pub description:    Option<String>,
    pub trigger_type:   String,
    pub trigger_config: Value,
    pub steps:          Value,
    pub is_active:      bool,
    pub version:        i32,
    pub created_by:     Option<Uuid>,
    pub created_at:     DateTime<Utc>,
    pub updated_at:     Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct WorkflowRun {
    pub run_id:          Uuid,
    pub workflow_id:     Uuid,
    pub tenant_id:       Uuid,
    pub trigger_event:   String,
    pub trigger_payload: Value,
    pub status:          String,
    pub current_step:    i32,
    pub step_results:    Value,
    pub error_message:   Option<String>,
    pub started_at:      DateTime<Utc>,
    pub completed_at:    Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct WorkflowStepType {
    pub step_type_code: String,
    pub display_name:   String,
    pub category:       String,
    pub config_schema:  Value,
    pub icon:           Option<String>,
    pub is_system:      bool,
}

#[derive(Debug, Deserialize)]
pub struct UpsertWorkflow {
    pub name:           String,
    pub description:    Option<String>,
    pub trigger_type:   String,
    pub trigger_config: Option<Value>,
    pub steps:          Value,
    pub is_active:      Option<bool>,
}

pub struct WorkflowService {
    db: PgPool,
}

impl WorkflowService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    pub async fn list_definitions(&self, tenant_id: Uuid) -> Result<Vec<WorkflowDefinition>, StatusCode> {
        sqlx::query_as!(
            WorkflowDefinition,
            r#"SELECT workflow_id, tenant_id, name, description, trigger_type,
                      trigger_config, steps, is_active, version, created_by,
                      created_at, updated_at
               FROM core_mdm.workflow_definitions
               WHERE tenant_id = $1
               ORDER BY created_at DESC"#,
            tenant_id
        )
        .fetch_all(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
    }

    pub async fn get_definition(&self, tenant_id: Uuid, workflow_id: Uuid) -> Result<WorkflowDefinition, StatusCode> {
        sqlx::query_as!(
            WorkflowDefinition,
            r#"SELECT workflow_id, tenant_id, name, description, trigger_type,
                      trigger_config, steps, is_active, version, created_by,
                      created_at, updated_at
               FROM core_mdm.workflow_definitions
               WHERE tenant_id = $1 AND workflow_id = $2"#,
            tenant_id, workflow_id
        )
        .fetch_optional(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)
    }

    pub async fn create_definition(
        &self,
        tenant_id: Uuid,
        actor: Uuid,
        req: UpsertWorkflow,
    ) -> Result<WorkflowDefinition, StatusCode> {
        let trigger_config = req.trigger_config.unwrap_or(serde_json::json!({}));
        let is_active = req.is_active.unwrap_or(true);

        sqlx::query_as!(
            WorkflowDefinition,
            r#"INSERT INTO core_mdm.workflow_definitions
                   (tenant_id, name, description, trigger_type, trigger_config, steps, is_active, created_by)
               VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
               RETURNING workflow_id, tenant_id, name, description, trigger_type,
                         trigger_config, steps, is_active, version, created_by,
                         created_at, updated_at"#,
            tenant_id, req.name, req.description, req.trigger_type,
            trigger_config, req.steps, is_active, actor
        )
        .fetch_one(&self.db)
        .await
        .map_err(|e| {
            if e.to_string().contains("unique") { StatusCode::CONFLICT } else { StatusCode::INTERNAL_SERVER_ERROR }
        })
    }

    pub async fn update_definition(
        &self,
        tenant_id: Uuid,
        workflow_id: Uuid,
        req: UpsertWorkflow,
    ) -> Result<WorkflowDefinition, StatusCode> {
        let trigger_config = req.trigger_config.unwrap_or(serde_json::json!({}));
        let is_active = req.is_active.unwrap_or(true);

        sqlx::query_as!(
            WorkflowDefinition,
            r#"UPDATE core_mdm.workflow_definitions
               SET name=$3, description=$4, trigger_type=$5, trigger_config=$6,
                   steps=$7, is_active=$8, version=version+1, updated_at=NOW()
               WHERE tenant_id=$1 AND workflow_id=$2
               RETURNING workflow_id, tenant_id, name, description, trigger_type,
                         trigger_config, steps, is_active, version, created_by,
                         created_at, updated_at"#,
            tenant_id, workflow_id, req.name, req.description,
            req.trigger_type, trigger_config, req.steps, is_active
        )
        .fetch_optional(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)
    }

    pub async fn delete_definition(&self, tenant_id: Uuid, workflow_id: Uuid) -> Result<(), StatusCode> {
        let rows = sqlx::query!(
            "DELETE FROM core_mdm.workflow_definitions WHERE tenant_id=$1 AND workflow_id=$2",
            tenant_id, workflow_id
        )
        .execute(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .rows_affected();

        if rows == 0 { Err(StatusCode::NOT_FOUND) } else { Ok(()) }
    }

    pub async fn toggle_definition(&self, tenant_id: Uuid, workflow_id: Uuid) -> Result<bool, StatusCode> {
        let row = sqlx::query!(
            r#"UPDATE core_mdm.workflow_definitions
               SET is_active = NOT is_active, updated_at = NOW()
               WHERE tenant_id=$1 AND workflow_id=$2
               RETURNING is_active"#,
            tenant_id, workflow_id
        )
        .fetch_optional(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;

        Ok(row.is_active)
    }

    pub async fn list_runs(&self, tenant_id: Uuid, workflow_id: Uuid) -> Result<Vec<WorkflowRun>, StatusCode> {
        sqlx::query_as!(
            WorkflowRun,
            r#"SELECT run_id, workflow_id, tenant_id, trigger_event, trigger_payload,
                      status, current_step, step_results, error_message,
                      started_at, completed_at
               FROM core_mdm.workflow_runs
               WHERE tenant_id=$1 AND workflow_id=$2
               ORDER BY started_at DESC LIMIT 100"#,
            tenant_id, workflow_id
        )
        .fetch_all(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
    }

    pub async fn trigger_run(
        &self,
        tenant_id: Uuid,
        workflow_id: Uuid,
        payload: Value,
    ) -> Result<WorkflowRun, StatusCode> {
        sqlx::query_as!(
            WorkflowRun,
            r#"INSERT INTO core_mdm.workflow_runs
                   (workflow_id, tenant_id, trigger_event, trigger_payload)
               VALUES ($1, $2, 'manual', $3)
               RETURNING run_id, workflow_id, tenant_id, trigger_event, trigger_payload,
                         status, current_step, step_results, error_message,
                         started_at, completed_at"#,
            workflow_id, tenant_id, payload
        )
        .fetch_one(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
    }

    pub async fn list_step_types(&self) -> Result<Vec<WorkflowStepType>, StatusCode> {
        sqlx::query_as!(
            WorkflowStepType,
            r#"SELECT step_type_code, display_name, category,
                      config_schema, icon, is_system
               FROM core_mdm.workflow_step_types
               ORDER BY category, display_name"#
        )
        .fetch_all(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
    }
}
