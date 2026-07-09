use sqlx::{PgPool, Row};
use uuid::Uuid;

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// EMAIL CLIENT
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// Which external email provider to use.
enum EmailProvider {
    /// Mailgun HTTP API.  Env: MAILGUN_API_KEY + MAILGUN_DOMAIN
    Mailgun { api_key: String, domain: String },
    /// SendGrid v3 Mail Send API.  Env: SENDGRID_API_KEY
    SendGrid { api_key: String },
}

struct EmailConfig {
    from_address: String, // EMAIL_FROM_ADDRESS  (default: noreply@nexusmdm.io)
    from_name:    String, // EMAIL_FROM_NAME     (default: Nexus MDM)
    provider:     EmailProvider,
}

pub struct EmailClient {
    http:   reqwest::Client,
    config: EmailConfig,
}

impl EmailClient {
    /// Reads configuration from environment variables. Returns `None` when
    /// neither Mailgun nor SendGrid is configured â€” callers treat this as
    /// "email delivery disabled" and log at warn level instead of failing.
    pub fn from_env() -> Option<Self> {
        let from_address = std::env::var("EMAIL_FROM_ADDRESS")
            .unwrap_or_else(|_| "noreply@nexusmdm.io".to_string());
        let from_name = std::env::var("EMAIL_FROM_NAME")
            .unwrap_or_else(|_| "Azile MDM".to_string());

        let provider = if let (Ok(key), Ok(domain)) = (
            std::env::var("MAILGUN_API_KEY"),
            std::env::var("MAILGUN_DOMAIN"),
        ) {
            EmailProvider::Mailgun { api_key: key, domain }
        } else if let Ok(key) = std::env::var("SENDGRID_API_KEY") {
            EmailProvider::SendGrid { api_key: key }
        } else {
            return None;
        };

        Some(Self {
            http:   reqwest::Client::new(),
            config: EmailConfig { from_address, from_name, provider },
        })
    }

    /// Send a plain-text email.  Non-blocking â€” errors are logged, not bubbled.
    pub async fn send(&self, to: &str, subject: &str, body: &str) {
        let result = match &self.config.provider {
            EmailProvider::Mailgun { api_key, domain } => {
                self.send_mailgun(api_key, domain, to, subject, body).await
            }
            EmailProvider::SendGrid { api_key } => {
                self.send_sendgrid(api_key, to, subject, body).await
            }
        };
        if let Err(e) = result {
            tracing::warn!(to, subject, error=%e, "email delivery failed");
        }
    }

    async fn send_mailgun(
        &self,
        api_key: &str,
        domain:  &str,
        to:      &str,
        subject: &str,
        body:    &str,
    ) -> anyhow::Result<()> {
        let url = format!("https://api.mailgun.net/v3/{}/messages", domain);
        let from = format!("{} <{}>", self.config.from_name, self.config.from_address);
        let resp = self
            .http
            .post(&url)
            .basic_auth("api", Some(api_key))
            .form(&[
                ("from",    from.as_str()),
                ("to",      to),
                ("subject", subject),
                ("text",    body),
            ])
            .send()
            .await?;
        if !resp.status().is_success() {
            let status = resp.status();
            let text   = resp.text().await.unwrap_or_default();
            anyhow::bail!("Mailgun {} â€” {}", status, text);
        }
        Ok(())
    }

    async fn send_sendgrid(
        &self,
        api_key: &str,
        to:      &str,
        subject: &str,
        body:    &str,
    ) -> anyhow::Result<()> {
        let payload = serde_json::json!({
            "personalizations": [{ "to": [{ "email": to }] }],
            "from": {
                "email": self.config.from_address,
                "name":  self.config.from_name
            },
            "subject": subject,
            "content": [{ "type": "text/plain", "value": body }]
        });
        let resp = self
            .http
            .post("https://api.sendgrid.com/v3/mail/send")
            .bearer_auth(api_key)
            .json(&payload)
            .send()
            .await?;
        if !resp.status().is_success() {
            let status = resp.status();
            let text   = resp.text().await.unwrap_or_default();
            anyhow::bail!("SendGrid {} â€” {}", status, text);
        }
        Ok(())
    }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// SLACK CLIENT
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

pub struct SlackClient {
    http:        reqwest::Client,
    webhook_url: String,
}

impl SlackClient {
    /// Returns `None` when `SLACK_WEBHOOK_URL` is not configured.
    pub fn from_env() -> Option<Self> {
        std::env::var("SLACK_WEBHOOK_URL").ok().map(|url| Self {
            http:        reqwest::Client::new(),
            webhook_url: url,
        })
    }

    /// Post a notification to Slack. Non-blocking â€” errors are logged, not bubbled.
    pub async fn send(&self, title: &str, body: &str, severity: &str) {
        let color = match severity {
            "critical" => "#FF0000",
            "warning"  => "#FFA500",
            _          => "#36A64F",
        };
        let payload = serde_json::json!({
            "attachments": [{
                "color":  color,
                "title":  format!("[{}] {}", severity.to_uppercase(), title),
                "text":   body,
                "footer": "Azile AI MDM"
            }]
        });
        match self.http.post(&self.webhook_url).json(&payload).send().await {
            Ok(resp) if resp.status().is_success() => {}
            Ok(resp)  => tracing::warn!(status=%resp.status(), "Slack webhook rejected"),
            Err(e)    => tracing::warn!(error=%e, "Slack webhook delivery failed"),
        }
    }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// NOTIFICATION SERVICE
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

pub struct NotificationService {
    db:           PgPool,
    email_client: Option<std::sync::Arc<EmailClient>>,
    slack_client: Option<std::sync::Arc<SlackClient>>,
}

impl NotificationService {
    pub fn new(db: PgPool) -> Self {
        let email_client = EmailClient::from_env().map(std::sync::Arc::new);
        if email_client.is_none() {
            tracing::info!(
                "Email delivery disabled â€” set MAILGUN_API_KEY/MAILGUN_DOMAIN \
                 or SENDGRID_API_KEY to enable"
            );
        }
        let slack_client = SlackClient::from_env().map(std::sync::Arc::new);
        if slack_client.is_none() {
            tracing::info!("Slack notifications disabled â€” set SLACK_WEBHOOK_URL to enable");
        }
        Self { db, email_client, slack_client }
    }

    pub async fn notify(
        &self,
        tenant_id:  Uuid,
        user_id:    Option<Uuid>,
        event_type: &str,
        title:      &str,
        body:       &str,
        severity:   &str,
        metadata:   serde_json::Value,
    ) -> Result<(), sqlx::Error> {
        // 1. Write to in-app inbox (always).
        sqlx::query(
            r#"
            INSERT INTO notifications.inbox (tenant_id, user_id, event_type, title, body, severity, metadata)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            "#,
        )
        .bind(tenant_id)
        .bind(user_id)
        .bind(event_type)
        .bind(title)
        .bind(body)
        .bind(severity)
        .bind(metadata)
        .execute(&self.db)
        .await?;

        // 2. Fire-and-forget Slack + email for warning/critical events.
        if matches!(severity, "warning" | "critical") {
            let title_owned    = title.to_owned();
            let body_owned     = body.to_owned();
            let severity_owned = severity.to_owned();

            if let Some(slack_client) = &self.slack_client {
                let slack = std::sync::Arc::clone(slack_client);
                let t = title_owned.clone();
                let b = body_owned.clone();
                let s = severity_owned.clone();
                tokio::spawn(async move { slack.send(&t, &b, &s).await });
            }

            if let Some(email_client) = &self.email_client {
                let email_client = std::sync::Arc::clone(email_client);
                let db           = self.db.clone();
                let subject      = format!("[Nexus MDM] {}", title_owned);

                tokio::spawn(async move {
                    let emails = fetch_admin_emails(&db, tenant_id, user_id).await;
                    for email in emails {
                        email_client.send(&email, &subject, &body_owned).await;
                    }
                });
            }
        }

        Ok(())
    }

    /// Returns true if an unread notification of the given type was created for this
    /// tenant within the last 24 hours â€” used to debounce quota warnings.
    async fn has_recent(&self, tenant_id: Uuid, event_type: &str) -> bool {
        sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FROM notifications.inbox \
             WHERE tenant_id = $1 AND event_type = $2 \
             AND created_at > NOW() - INTERVAL '24 hours'",
        )
        .bind(tenant_id)
        .bind(event_type)
        .fetch_one(&self.db)
        .await
        .unwrap_or(0)
            > 0
    }

    pub async fn check_and_notify_record_quota(
        &self,
        tenant_id: Uuid,
        current:   i64,
        limit:     i64,
    ) -> Result<(), sqlx::Error> {
        if limit <= 0 {
            return Ok(());
        }
        let pct = current as f64 / limit as f64;
        let (event_type, title, body, severity) = if pct >= 0.95 {
            (
                "quota.records.warning_95pct",
                "Record quota critical â€” 95% used",
                format!("You've used {current} of {limit} records (â‰¥95%). Upgrade your plan before writes are blocked."),
                "critical",
            )
        } else if pct >= 0.80 {
            (
                "quota.records.warning_80pct",
                "Record quota warning â€” 80% used",
                format!("You've used {current} of {limit} records (â‰¥80%). Consider upgrading your plan."),
                "warning",
            )
        } else {
            return Ok(());
        };
        if !self.has_recent(tenant_id, event_type).await {
            self.notify(
                tenant_id, None, event_type, title, &body, severity,
                serde_json::json!({ "current": current, "limit": limit }),
            )
            .await?;
        }
        Ok(())
    }

    pub async fn check_and_notify_steward_quota(
        &self,
        tenant_id: Uuid,
        current:   i64,
        limit:     i64,
    ) -> Result<(), sqlx::Error> {
        if limit <= 0 {
            return Ok(());
        }
        let pct = current as f64 / limit as f64;
        let (event_type, title, body, severity) = if pct >= 0.95 {
            (
                "quota.stewards.warning_95pct",
                "Steward quota critical â€” 95% used",
                format!("{current} of {limit} steward seats filled (â‰¥95%). Upgrade to add more."),
                "critical",
            )
        } else if pct >= 0.80 {
            (
                "quota.stewards.warning_80pct",
                "Steward quota warning â€” 80% used",
                format!("{current} of {limit} steward seats filled (â‰¥80%)."),
                "warning",
            )
        } else {
            return Ok(());
        };
        if !self.has_recent(tenant_id, event_type).await {
            self.notify(
                tenant_id, None, event_type, title, &body, severity,
                serde_json::json!({ "current": current, "limit": limit }),
            )
            .await?;
        }
        Ok(())
    }

    pub async fn check_and_notify_domain_quota(
        &self,
        tenant_id: Uuid,
        current:   i64,
        limit:     i64,
    ) -> Result<(), sqlx::Error> {
        if limit <= 0 {
            return Ok(());
        }
        let pct = current as f64 / limit as f64;
        let (event_type, title, body, severity) = if pct >= 0.95 {
            (
                "quota.domains.warning_95pct",
                "Domain quota critical â€” 95% used",
                format!("{current} of {limit} entity types created (â‰¥95%)."),
                "critical",
            )
        } else if pct >= 0.80 {
            (
                "quota.domains.warning_80pct",
                "Domain quota warning â€” 80% used",
                format!("{current} of {limit} entity types created (â‰¥80%)."),
                "warning",
            )
        } else {
            return Ok(());
        };
        if !self.has_recent(tenant_id, event_type).await {
            self.notify(
                tenant_id, None, event_type, title, &body, severity,
                serde_json::json!({ "current": current, "limit": limit }),
            )
            .await?;
        }
        Ok(())
    }

    pub async fn notify_license_expiry(
        &self,
        tenant_id:      Uuid,
        days_remaining: i32,
    ) -> Result<(), sqlx::Error> {
        let (event_type, title, body, severity) = if days_remaining <= 7 {
            (
                "license.expiry.critical",
                "License expires within 7 days",
                format!("Your Nexus AI MDM license expires in {days_remaining} day(s). Contact sales immediately to avoid service disruption."),
                "critical",
            )
        } else if days_remaining <= 30 {
            (
                "license.expiry.warning",
                "License expiring soon",
                format!("Your license expires in {days_remaining} days. Contact sales to renew."),
                "warning",
            )
        } else {
            return Ok(());
        };
        if !self.has_recent(tenant_id, event_type).await {
            self.notify(
                tenant_id, None, event_type, title, &body, severity,
                serde_json::json!({ "days_remaining": days_remaining }),
            )
            .await?;
        }
        Ok(())
    }

    pub async fn list(
        &self,
        tenant_id: Uuid,
        page:      i64,
        page_size: i64,
    ) -> Result<(Vec<serde_json::Value>, i64), sqlx::Error> {
        let offset = (page - 1) * page_size;
        let rows = sqlx::query(
            r#"
            SELECT notification_id, tenant_id, user_id, event_type, title, body,
                   severity, is_read, metadata, created_at, read_at
            FROM   notifications.inbox
            WHERE  tenant_id = $1
            ORDER  BY created_at DESC
            LIMIT  $2 OFFSET $3
            "#,
        )
        .bind(tenant_id)
        .bind(page_size)
        .bind(offset)
        .fetch_all(&self.db)
        .await?;

        let items: Vec<serde_json::Value> = rows
            .iter()
            .map(|r| {
                let created_at: chrono::DateTime<chrono::Utc> = r.get("created_at");
                let read_at: Option<chrono::DateTime<chrono::Utc>> = r.get("read_at");
                serde_json::json!({
                    "notification_id": r.get::<Uuid, _>("notification_id").to_string(),
                    "event_type":      r.get::<String, _>("event_type"),
                    "title":           r.get::<String, _>("title"),
                    "body":            r.get::<String, _>("body"),
                    "severity":        r.get::<String, _>("severity"),
                    "is_read":         r.get::<bool, _>("is_read"),
                    "metadata":        r.get::<serde_json::Value, _>("metadata"),
                    "created_at":      created_at.to_rfc3339(),
                    "read_at":         read_at.map(|t| t.to_rfc3339()),
                })
            })
            .collect();

        let total: i64 = sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FROM notifications.inbox WHERE tenant_id = $1",
        )
        .bind(tenant_id)
        .fetch_one(&self.db)
        .await
        .unwrap_or(0);

        Ok((items, total))
    }

    pub async fn mark_read(
        &self,
        tenant_id:       Uuid,
        notification_id: Uuid,
    ) -> Result<bool, sqlx::Error> {
        let result = sqlx::query(
            "UPDATE notifications.inbox \
             SET is_read = true, read_at = NOW() \
             WHERE tenant_id = $1 AND notification_id = $2 AND is_read = false",
        )
        .bind(tenant_id)
        .bind(notification_id)
        .execute(&self.db)
        .await?;
        Ok(result.rows_affected() > 0)
    }

    pub async fn mark_all_read(&self, tenant_id: Uuid) -> Result<u64, sqlx::Error> {
        let result = sqlx::query(
            "UPDATE notifications.inbox \
             SET is_read = true, read_at = NOW() \
             WHERE tenant_id = $1 AND is_read = false",
        )
        .bind(tenant_id)
        .execute(&self.db)
        .await?;
        Ok(result.rows_affected())
    }

    pub async fn unread_count(&self, tenant_id: Uuid) -> Result<i64, sqlx::Error> {
        sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FROM notifications.inbox WHERE tenant_id = $1 AND is_read = false",
        )
        .bind(tenant_id)
        .fetch_one(&self.db)
        .await
    }

    // â”€â”€ Subscription management â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    pub async fn create_subscription(
        &self,
        tenant_id:        Uuid,
        subscriber_id:    Uuid,
        subscriber_type:  &str,
        event_types:      Vec<String>,
        entity_type:      Option<&str>,
        entity_id:        Option<Uuid>,
        delivery_channel: &str,
        delivery_target:  Option<&str>,
    ) -> Result<serde_json::Value, sqlx::Error> {
        let row = sqlx::query(
            r#"
            INSERT INTO core_mdm.notification_subscriptions
                (tenant_id, subscriber_id, subscriber_type, event_types, entity_type,
                 entity_id, delivery_channel, delivery_target)
            VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
            ON CONFLICT DO NOTHING
            RETURNING id, subscriber_id, subscriber_type, event_types, entity_type,
                      entity_id, delivery_channel, delivery_target, is_active, created_at
            "#,
        )
        .bind(tenant_id)
        .bind(subscriber_id)
        .bind(subscriber_type)
        .bind(&event_types)
        .bind(entity_type)
        .bind(entity_id)
        .bind(delivery_channel)
        .bind(delivery_target)
        .fetch_optional(&self.db)
        .await?;

        match row {
            Some(r) => Ok(subscription_row_to_json(&r)),
            None    => Ok(serde_json::json!({ "duplicate": true })),
        }
    }

    pub async fn list_subscriptions(
        &self,
        tenant_id:     Uuid,
        subscriber_id: Option<Uuid>,
    ) -> Result<Vec<serde_json::Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT id, subscriber_id, subscriber_type, event_types, entity_type,
                   entity_id, delivery_channel, delivery_target, is_active, created_at
            FROM core_mdm.notification_subscriptions
            WHERE tenant_id = $1
              AND ($2::uuid IS NULL OR subscriber_id = $2)
            ORDER BY created_at DESC
            "#,
        )
        .bind(tenant_id)
        .bind(subscriber_id)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| subscription_row_to_json(r)).collect())
    }

    pub async fn delete_subscription(
        &self,
        tenant_id: Uuid,
        id:        Uuid,
    ) -> Result<bool, sqlx::Error> {
        let r = sqlx::query(
            "DELETE FROM core_mdm.notification_subscriptions WHERE id = $1 AND tenant_id = $2",
        )
        .bind(id)
        .bind(tenant_id)
        .execute(&self.db)
        .await?;
        Ok(r.rows_affected() > 0)
    }

    // â”€â”€ Event dispatch â€” routes events to all matching subscribers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    /// Dispatch an event to all active subscriptions that match it.
    /// Called fire-and-forget from entity_service, merge_service, etc.
    pub async fn dispatch_event(
        &self,
        tenant_id:   Uuid,
        event_type:  &str,
        entity_type: Option<&str>,
        entity_id:   Option<Uuid>,
        title:       &str,
        body:        &str,
        metadata:    serde_json::Value,
    ) {
        let rows = sqlx::query(
            r#"
            SELECT subscriber_id, subscriber_type, delivery_channel, delivery_target
            FROM core_mdm.notification_subscriptions
            WHERE tenant_id = $1
              AND is_active  = true
              AND ($2 = ANY(event_types) OR event_types = '{}')
              AND (entity_type IS NULL OR $3::text IS NULL OR entity_type = $3)
              AND (entity_id   IS NULL OR $4::uuid IS NULL OR entity_id   = $4)
            "#,
        )
        .bind(tenant_id)
        .bind(event_type)
        .bind(entity_type)
        .bind(entity_id)
        .fetch_all(&self.db)
        .await
        .unwrap_or_default();

        for row in rows {
            use sqlx::Row;
            let subscriber_id:   Uuid   = row.get("subscriber_id");
            let delivery_channel: String = row.get("delivery_channel");
            let delivery_target: Option<String> = row.get("delivery_target");

            match delivery_channel.as_str() {
                "InApp" => {
                    let _ = self.notify(
                        tenant_id,
                        Some(subscriber_id),
                        event_type,
                        title,
                        body,
                        "info",
                        metadata.clone(),
                    ).await;
                }
                "Email" => {
                    if let (Some(email_client), Some(target)) = (&self.email_client, &delivery_target) {
                        let email_client = std::sync::Arc::clone(email_client);
                        let subject = format!("[Nexus MDM] {}", title);
                        let to      = target.clone();
                        let body_s  = body.to_owned();
                        tokio::spawn(async move {
                            email_client.send(&to, &subject, &body_s).await;
                        });
                    }
                }
                "Slack" => {
                    if let Some(slack_client) = &self.slack_client {
                        let slack = std::sync::Arc::clone(slack_client);
                        let t = title.to_owned();
                        let b = body.to_owned();
                        tokio::spawn(async move {
                            slack.send(&t, &b, "info").await;
                        });
                    } else if let Some(target) = &delivery_target {
                        // Per-subscription Slack webhook URL override
                        let http   = reqwest::Client::new();
                        let target = target.clone();
                        let t      = title.to_owned();
                        let b      = body.to_owned();
                        tokio::spawn(async move {
                            let payload = serde_json::json!({
                                "text": format!("*{}*\n{}", t, b)
                            });
                            let _ = http.post(&target).json(&payload).send().await;
                        });
                    }
                }
                "Webhook" => {
                    if let Some(target) = &delivery_target {
                        let http    = reqwest::Client::new();
                        let target  = target.clone();
                        let payload = serde_json::json!({
                            "event_type":  event_type,
                            "entity_type": entity_type,
                            "entity_id":   entity_id,
                            "title":       title,
                            "body":        body,
                            "metadata":    metadata.clone(),
                        });
                        tokio::spawn(async move {
                            let _ = http.post(&target).json(&payload).send().await;
                        });
                    }
                }
                _ => {}
            }
        }
    }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// HELPERS
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

fn subscription_row_to_json(r: &sqlx::postgres::PgRow) -> serde_json::Value {
    use sqlx::Row;
    serde_json::json!({
        "id":               r.get::<Uuid, _>("id"),
        "subscriber_id":    r.get::<Uuid, _>("subscriber_id"),
        "subscriber_type":  r.get::<String, _>("subscriber_type"),
        "event_types":      r.get::<Vec<String>, _>("event_types"),
        "entity_type":      r.get::<Option<String>, _>("entity_type"),
        "entity_id":        r.get::<Option<Uuid>, _>("entity_id"),
        "delivery_channel": r.get::<String, _>("delivery_channel"),
        "delivery_target":  r.get::<Option<String>, _>("delivery_target"),
        "is_active":        r.get::<bool, _>("is_active"),
        "created_at":       r.get::<chrono::DateTime<chrono::Utc>, _>("created_at"),
    })
}

/// Fetch email addresses to notify for a given event.
///
/// - When `user_id` is Some, send only to that user.
/// - When `user_id` is None (system event), send to all Admin/BusinessAdmin
///   members of the tenant.
async fn fetch_admin_emails(
    db:        &PgPool,
    tenant_id: Uuid,
    user_id:   Option<Uuid>,
) -> Vec<String> {
    if let Some(uid) = user_id {
        // Single-user notification â€” look up their email directly.
        let row = sqlx::query_scalar::<_, String>(
            "SELECT email FROM core_mdm.identities WHERE identity_id = $1",
        )
        .bind(uid)
        .fetch_optional(db)
        .await
        .unwrap_or(None);
        return row.into_iter().collect();
    }

    // System event â€” notify all admins for this tenant.
    sqlx::query_scalar::<_, String>(
        r#"
        SELECT i.email
        FROM   core_mdm.identities         i
        JOIN   core_mdm.tenant_memberships m ON m.identity_id = i.identity_id
        WHERE  m.tenant_id = $1
          AND  m.role IN ('Admin', 'BusinessAdmin', 'SuperAdmin')
          AND  m.status = 'active'
        "#,
    )
    .bind(tenant_id)
    .fetch_all(db)
    .await
    .unwrap_or_default()
}
