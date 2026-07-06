use std::sync::Arc;
use std::time::Duration;

use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::services::notification_service::NotificationService;

/// Runs once at startup and then every 24 hours.
/// Queries all active licenses expiring within 30 days and fires
/// debounced in-app notifications via NotificationService.
pub async fn run(db: PgPool, notification_service: Arc<NotificationService>) {
    // Tick immediately so expiry warnings appear on every restart too.
    let mut interval = tokio::time::interval(Duration::from_secs(24 * 3_600));
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

    loop {
        interval.tick().await;
        check_once(&db, &notification_service).await;
    }
}

async fn check_once(db: &PgPool, ns: &Arc<NotificationService>) {
    let result = sqlx::query(
        r#"
        SELECT tenant_id,
               GREATEST(0, EXTRACT(DAY FROM (expires_at - NOW()))::int) AS days_remaining
        FROM   core_mdm.tenant_licenses
        WHERE  expires_at IS NOT NULL
          AND  status      = 'active'
          AND  expires_at  > NOW()
          AND  expires_at <= NOW() + INTERVAL '30 days'
        "#,
    )
    .fetch_all(db)
    .await;

    match result {
        Ok(rows) => {
            let count = rows.len();
            for row in &rows {
                let tenant_id: Uuid = row.get("tenant_id");
                let days: i32       = row.get("days_remaining");
                if let Err(e) = ns.notify_license_expiry(tenant_id, days).await {
                    tracing::warn!(error=%e, %tenant_id, "license expiry notification failed");
                }
            }
            tracing::info!(count, "license expiry check complete");
        }
        Err(e) => tracing::error!(error=%e, "license expiry query failed"),
    }
}
