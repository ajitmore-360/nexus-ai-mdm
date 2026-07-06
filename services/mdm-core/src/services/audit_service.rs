use sqlx::PgPool;
use uuid::Uuid;
use serde_json::Value;
use tracing::warn;

pub struct AuditService {
    db: PgPool,
}

pub struct AuditEvent {
    pub tenant_id:     Uuid,
    pub event_type:    String,
    pub actor_id:      Option<Uuid>,
    pub resource_type: String,
    pub resource_id:   String,
    pub metadata:      Value,
    /// Snapshot of the resource state before the change. When both `before`
    /// and `after` are provided, a field-level diff is computed and merged
    /// into `metadata` under the keys `"before"`, `"after"`, and `"diff"`.
    pub before:        Option<Value>,
    /// Snapshot of the resource state after the change.
    pub after:         Option<Value>,
}

/// Compute a shallow JSON diff: returns an object with only the keys whose
/// values differ between `before` and `after`. Each entry is
/// `{ "from": <old>, "to": <new> }`. New keys (absent in before) and removed
/// keys (absent in after) are also included.
pub fn compute_diff(before: &Value, after: &Value) -> Value {
    let before_obj = before.as_object();
    let after_obj  = after.as_object();

    let mut diff = serde_json::Map::new();

    // Keys in after (changed or added)
    if let Some(after_map) = after_obj {
        for (key, new_val) in after_map {
            let old_val = before_obj.and_then(|m| m.get(key));
            if old_val.map(|v| v != new_val).unwrap_or(true) {
                diff.insert(
                    key.clone(),
                    serde_json::json!({
                        "from": old_val.unwrap_or(&Value::Null),
                        "to":   new_val,
                    }),
                );
            }
        }
    }

    // Keys removed (in before but not in after)
    if let Some(before_map) = before_obj {
        for key in before_map.keys() {
            if after_obj.map(|m| !m.contains_key(key)).unwrap_or(true) {
                diff.insert(
                    key.clone(),
                    serde_json::json!({ "from": before_map[key], "to": Value::Null }),
                );
            }
        }
    }

    Value::Object(diff)
}

impl AuditService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    pub async fn log(&self, event: AuditEvent) -> Result<(), sqlx::Error> {
        let metadata = enrich_metadata(event.metadata, event.before.as_ref(), event.after.as_ref());
        sqlx::query(
            "INSERT INTO core_mdm.audit_events
                 (event_id, tenant_id, event_type, actor_id, resource_type, resource_id, metadata, created_at)
             VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, NOW())",
        )
        .bind(event.tenant_id)
        .bind(&event.event_type)
        .bind(event.actor_id)
        .bind(&event.resource_type)
        .bind(&event.resource_id)
        .bind(&metadata)
        .execute(&self.db)
        .await?;
        Ok(())
    }

    /// Fire-and-forget: spawns a Tokio task so the caller is never blocked.
    /// Retries up to 3 times with exponential back-off (200 ms, 400 ms) before
    /// giving up and logging a warning — transient connection blips will not
    /// silently drop audit events.
    pub fn log_background(&self, event: AuditEvent) {
        let db = self.db.clone();
        let metadata = enrich_metadata(event.metadata, event.before.as_ref(), event.after.as_ref());
        tokio::spawn(async move {
            for attempt in 0u8..3 {
                let result = sqlx::query(
                    "INSERT INTO core_mdm.audit_events
                         (event_id, tenant_id, event_type, actor_id, resource_type, resource_id, metadata, created_at)
                     VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, NOW())",
                )
                .bind(event.tenant_id)
                .bind(&event.event_type)
                .bind(event.actor_id)
                .bind(&event.resource_type)
                .bind(&event.resource_id)
                .bind(&metadata)
                .execute(&db)
                .await;

                match result {
                    Ok(_) => return,
                    Err(e) => {
                        warn!(error=%e, attempt, "background audit log write failed");
                        if attempt < 2 {
                            tokio::time::sleep(
                                std::time::Duration::from_millis(200u64 << attempt),
                            )
                            .await;
                        }
                    }
                }
            }
        });
    }
}

/// Merge before/after snapshots and diff into the event metadata object.
fn enrich_metadata(mut meta: Value, before: Option<&Value>, after: Option<&Value>) -> Value {
    if let (Some(b), Some(a)) = (before, after) {
        let diff = compute_diff(b, a);
        if let Some(obj) = meta.as_object_mut() {
            obj.insert("before".to_string(), b.clone());
            obj.insert("after".to_string(),  a.clone());
            obj.insert("diff".to_string(),   diff);
        }
    }
    meta
}
