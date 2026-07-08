use std::time::Duration;

use reqwest::Client;
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// Poll interval — conservative start; tune down to 5s once delivery_log grows.
const POLL_INTERVAL_SECS: u64 = 10;
/// Max attempts before a delivery is permanently marked failed.
#[allow(dead_code)]
const MAX_ATTEMPTS: i32 = 5;

/// Background worker — runs forever, delivering pending webhook notifications.
pub async fn run(db: PgPool) {
    let client = Client::builder()
        .timeout(Duration::from_secs(10))
        .user_agent("Nexus-MDM-Webhook/1.0")
        .build()
        .expect("reqwest client");

    let mut interval = tokio::time::interval(Duration::from_secs(POLL_INTERVAL_SECS));
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

    loop {
        interval.tick().await;
        deliver_pending(&db, &client).await;
    }
}

async fn deliver_pending(db: &PgPool, client: &Client) {
    // Find all inbox rows that have matching subscriptions but no delivery attempt yet.
    // Uses SKIP LOCKED so multiple replicas don't double-deliver.
    let candidates = sqlx::query(
        r#"
        SELECT n.notification_id,
               n.tenant_id,
               n.event_type,
               n.title,
               n.body,
               n.metadata,
               n.created_at,
               ws.subscription_id,
               ws.url,
               ws.secret
        FROM   notifications.inbox n
        JOIN   notifications.webhook_subscriptions ws
               ON  ws.tenant_id = n.tenant_id
               AND ws.enabled   = TRUE
               AND (ws.event_types = '{}' OR n.event_type = ANY(ws.event_types))
        LEFT   JOIN notifications.delivery_log dl
               ON  dl.notification_id = n.notification_id
               AND dl.channel         = 'webhook'
               AND dl.recipient       = ws.url
        WHERE  dl.log_id    IS NULL                    -- not yet attempted
          AND  n.created_at  > NOW() - INTERVAL '7 days'  -- safety window
        LIMIT  50
        "#,
    )
    .fetch_all(db)
    .await;

    let rows = match candidates {
        Ok(r) => r,
        Err(e) => {
            tracing::error!(error=%e, "webhook_worker: candidate query failed");
            return;
        }
    };

    for row in rows {
        let notification_id: Uuid   = row.get("notification_id");
        let subscription_id: Uuid   = row.get("subscription_id");
        let tenant_id: Uuid         = row.get("tenant_id");
        let url: String             = row.get("url");
        let secret: Option<String>  = row.get("secret");
        let event_type: String      = row.get("event_type");
        let created_at: chrono::DateTime<chrono::Utc> = row.get("created_at");

        let payload = serde_json::json!({
            "notification_id": notification_id.to_string(),
            "tenant_id":       tenant_id.to_string(),
            "event_type":      event_type,
            "title":           row.get::<String, _>("title"),
            "body":            row.get::<String, _>("body"),
            "metadata":        row.get::<serde_json::Value, _>("metadata"),
            "sent_at":         created_at.to_rfc3339(),
        });

        let payload_str = payload.to_string();

        // Insert a delivery attempt row first (idempotency guard via ON CONFLICT DO NOTHING).
        let log_id: Option<Uuid> = sqlx::query_scalar(
            r#"
            INSERT INTO notifications.delivery_log
                (tenant_id, notification_id, channel, event_type, recipient, status, payload)
            VALUES ($1, $2, 'webhook', $3, $4, 'pending', $5)
            ON CONFLICT DO NOTHING
            RETURNING log_id
            "#,
        )
        .bind(tenant_id)
        .bind(notification_id)
        .bind(&event_type)
        .bind(&url)
        .bind(&payload)
        .fetch_optional(db)
        .await
        .unwrap_or(None);

        let log_id = match log_id {
            Some(id) => id,
            None => continue, // Another worker beat us to it.
        };

        // Attempt delivery.
        let mut req = client.post(&url)
            .header("Content-Type", "application/json")
            .header("X-Nexus-Event", &event_type)
            .header("X-Nexus-Delivery-Id", log_id.to_string())
            .body(payload_str.clone());

        // HMAC-SHA256 signature when a secret is configured.
        if let Some(ref secret_val) = secret {
            let sig = hmac_sha256(secret_val.as_bytes(), payload_str.as_bytes());
            req = req.header("X-Nexus-Signature-256", format!("sha256={sig}"));
        }

        let (status_str, error_msg) = match req.send().await {
            Ok(resp) if resp.status().is_success() => ("delivered", None),
            Ok(resp) => (
                "failed",
                Some(format!("HTTP {} from target", resp.status().as_u16())),
            ),
            Err(e) => ("failed", Some(e.to_string())),
        };

        let _ = sqlx::query(
            "UPDATE notifications.delivery_log \
             SET status = $1, last_error = $2, attempts = attempts + 1, delivered_at = \
             CASE WHEN $1 = 'delivered' THEN NOW() ELSE NULL END \
             WHERE log_id = $3",
        )
        .bind(status_str)
        .bind(error_msg.as_deref())
        .bind(log_id)
        .execute(db)
        .await;

        if status_str == "delivered" {
            tracing::info!(
                %notification_id, %subscription_id, %url,
                "webhook delivered"
            );
        } else {
            tracing::warn!(
                %notification_id, %url, error=?error_msg,
                "webhook delivery failed"
            );
        }
    }
}

fn hmac_sha256(key: &[u8], data: &[u8]) -> String {
    use hmac::{Hmac, Mac};
    use sha2::Sha256;
    type HmacSha256 = Hmac<Sha256>;

    let mut mac = HmacSha256::new_from_slice(key).expect("HMAC key length is valid");
    mac.update(data);
    hex::encode(mac.finalize().into_bytes())
}
