use anyhow::Result;
use chrono::Utc;
use reqwest::Client;
use sqlx::PgPool;
use uuid::Uuid;

use crate::hub::PushNotification;

const MAX_ATTEMPTS: u32 = 3;

/// Fetch all enabled webhook subscriptions for the tenant that match the event type,
/// then attempt delivery to each with up to MAX_ATTEMPTS retries (exponential backoff).
pub async fn dispatch(pool: &PgPool, http: &Client, notif: &PushNotification) -> Result<()> {
    use sqlx::Row;

    // Load active subscriptions matching this event type (or empty event_types = all).
    let rows = sqlx::query(
        r#"
        SELECT subscription_id, url, secret
        FROM notifications.webhook_subscriptions
        WHERE tenant_id = $1
          AND enabled   = TRUE
          AND (event_types = '{}' OR $2 = ANY(event_types))
        "#,
    )
    .bind(notif.tenant_id)
    .bind(&notif.notification_type)
    .fetch_all(pool)
    .await?;

    if rows.is_empty() {
        return Ok(());
    }

    let payload = serde_json::to_string(notif)?;
    let log_id  = Uuid::new_v4();

    for row in &rows {
        let url:    String      = row.get("url");
        let secret: Option<String> = row.get("secret");

        let mut last_error = String::new();
        let mut delivered  = false;

        for attempt in 1..=MAX_ATTEMPTS {
            let mut req = http
                .post(&url)
                .header("Content-Type", "application/json")
                .header("X-Nexus-Event",         &notif.notification_type)
                .header("X-Nexus-Notification-Id", notif.notification_id.to_string())
                .header("X-Nexus-Tenant-Id",      notif.tenant_id.to_string())
                .body(payload.clone());

            if let Some(secret) = &secret {
                let sig = hmac_sha256_hex(secret, &payload);
                req = req.header("X-Nexus-Signature", format!("sha256={}", sig));
            }

            match req.send().await {
                Ok(resp) if resp.status().is_success() => {
                    delivered = true;
                    tracing::debug!(url=%url, attempt, "webhook delivered");
                    break;
                }
                Ok(resp) => {
                    last_error = format!("HTTP {}", resp.status());
                    tracing::warn!(url=%url, attempt, status=%resp.status(), "webhook delivery failed");
                }
                Err(e) => {
                    last_error = e.to_string();
                    tracing::warn!(url=%url, attempt, error=%e, "webhook network error");
                }
            }

            if attempt < MAX_ATTEMPTS {
                let backoff = std::time::Duration::from_secs(2u64.pow(attempt));
                tokio::time::sleep(backoff).await;
            }
        }

        let status   = if delivered { "delivered" } else { "failed" };
        let now      = Utc::now();
        let delivered_at = if delivered { Some(now) } else { None };

        let _ = sqlx::query(
            r#"
            INSERT INTO notifications.delivery_log
                (log_id, tenant_id, notification_id, channel, event_type, recipient,
                 status, attempts, last_error, payload, created_at, delivered_at)
            VALUES ($1,$2,$3,'webhook',$4,$5,$6,$7,$8,$9,$10,$11)
            "#,
        )
        .bind(log_id)
        .bind(notif.tenant_id)
        .bind(notif.notification_id)
        .bind(&notif.notification_type)
        .bind(&url)
        .bind(status)
        .bind(MAX_ATTEMPTS as i32)
        .bind(if last_error.is_empty() { None } else { Some(last_error.as_str()) })
        .bind(serde_json::to_value(notif).unwrap_or_default())
        .bind(now)
        .bind(delivered_at)
        .execute(pool)
        .await;
    }

    Ok(())
}

fn hmac_sha256_hex(key: &str, data: &str) -> String {
    use hmac::{Hmac, Mac};
    use sha2::Sha256;

    type HmacSha256 = Hmac<Sha256>;

    let mut mac = HmacSha256::new_from_slice(key.as_bytes())
        .expect("HMAC accepts any key length");
    mac.update(data.as_bytes());
    hex::encode(mac.finalize().into_bytes())
}
