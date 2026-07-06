use anyhow::{Context, Result};
use chrono::Utc;
use lettre::{
    message::{header::ContentType, MultiPart, SinglePart},
    transport::smtp::authentication::Credentials,
    AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor,
};
use sqlx::PgPool;
use uuid::Uuid;

use crate::hub::PushNotification;

// ─────────────────────────────────────────────────────────────────────────────
// Transactional email entry points
// ─────────────────────────────────────────────────────────────────────────────

/// Send a user invite email with the activation link.
/// Gracefully no-ops (logs only) when SMTP_HOST is not configured.
pub async fn send_invite_email(
    to: &str,
    display_name: &str,
    activation_url: &str,
    invited_by: Option<&str>,
) -> Result<()> {
    let subject = "You've been invited to Nexus AI MDM".to_string();
    let html = invite_html(display_name, activation_url, invited_by);
    let plain = invite_plain(display_name, activation_url, invited_by);
    send(to, &subject, &html, &plain).await
}

// ─────────────────────────────────────────────────────────────────────────────
// Push-notification email dispatch (existing, kept for webhook/notify flow)
// ─────────────────────────────────────────────────────────────────────────────

pub async fn dispatch(pool: &PgPool, notif: &PushNotification, to: &str) -> Result<()> {
    let subject = &notif.title;
    let html    = format!("<p>{}</p>", &notif.body);
    let plain   = notif.body.clone();

    // `send()` retries internally up to MAX_ATTEMPTS; record the outcome.
    let result = send(to, subject, &html, &plain).await;

    let log_id = Uuid::new_v4();
    let now    = Utc::now();
    let status = if result.is_ok() { "delivered" } else { "failed" };
    let err    = result.as_ref().err().map(|e| e.to_string());

    let _ = sqlx::query(
        r#"
        INSERT INTO notifications.delivery_log
            (log_id, tenant_id, notification_id, channel, event_type, recipient,
             status, attempts, last_error, payload, created_at, delivered_at)
        VALUES ($1,$2,$3,'email',$4,$5,$6,3,$7,$8,$9,$10)
        "#,
    )
    .bind(log_id)
    .bind(notif.tenant_id)
    .bind(notif.notification_id)
    .bind(&notif.notification_type)
    .bind(to)
    .bind(status)
    .bind(err.as_deref())
    .bind(serde_json::to_value(notif).unwrap_or_default())
    .bind(now)
    .bind(if result.is_ok() { Some(now) } else { None })
    .execute(pool)
    .await;

    result
}

// ─────────────────────────────────────────────────────────────────────────────
// Core SMTP send with retry
// ─────────────────────────────────────────────────────────────────────────────

/// Returns true for errors that are definitively permanent (bad address, parse
/// failure, auth rejection) and should NOT be retried.
fn is_permanent_error(e: &anyhow::Error) -> bool {
    let msg = e.to_string().to_lowercase();
    msg.contains("invalid")
        || msg.contains("parse")
        || msg.contains("535")   // SMTP auth failed
        || msg.contains("550")   // mailbox unavailable / policy
        || msg.contains("551")   // user not local
        || msg.contains("553")   // mailbox name invalid
}

/// Attempt to send up to `MAX_ATTEMPTS` times with exponential back-off.
/// Permanent errors (bad address, auth) short-circuit immediately.
async fn send(to: &str, subject: &str, html: &str, plain: &str) -> Result<()> {
    const MAX_ATTEMPTS: u32 = 3;

    let smtp_host = std::env::var("SMTP_HOST").unwrap_or_default();

    if smtp_host.is_empty() {
        tracing::warn!(
            to      = %to,
            subject = %subject,
            "EMAIL NOT SENT — SMTP_HOST is unset. \
             Set SMTP_HOST (and optionally SMTP_PORT/SMTP_USER/SMTP_PASS) to enable delivery. \
             For local dev use Mailhog on port 1025."
        );
        tracing::debug!(body = %plain, "email body (plain text, not delivered)");
        return Ok(());
    }

    let smtp_port: u16 = std::env::var("SMTP_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(587);

    let from_addr = std::env::var("SMTP_FROM")
        .unwrap_or_else(|_| "Nexus AI MDM <noreply@nexus-mdm.io>".to_string());

    // Build the message once — it is cheaply cloneable via re-building.
    let build_message = || -> Result<Message> {
        Message::builder()
            .from(from_addr.parse().context("invalid SMTP_FROM address")?)
            .to(to.parse().context("invalid recipient address")?)
            .subject(subject)
            .multipart(
                MultiPart::alternative()
                    .singlepart(
                        SinglePart::builder()
                            .header(ContentType::TEXT_PLAIN)
                            .body(plain.to_string()),
                    )
                    .singlepart(
                        SinglePart::builder()
                            .header(ContentType::TEXT_HTML)
                            .body(html.to_string()),
                    ),
            )
            .context("failed to build email message")
    };

    // Build the transport once — it manages its own connection pool.
    let insecure = smtp_port == 1025
        || std::env::var("SMTP_INSECURE").map(|v| v == "true").unwrap_or(false);

    let mailer: AsyncSmtpTransport<Tokio1Executor> = if insecure {
        AsyncSmtpTransport::<Tokio1Executor>::builder_dangerous(&smtp_host)
            .port(smtp_port)
            .build()
    } else {
        let smtp_user = std::env::var("SMTP_USER").ok();
        let smtp_pass = std::env::var("SMTP_PASS").ok();
        let mut builder = AsyncSmtpTransport::<Tokio1Executor>::relay(&smtp_host)
            .context("invalid SMTP_HOST")?
            .port(smtp_port);
        if let (Some(u), Some(p)) = (smtp_user, smtp_pass) {
            builder = builder.credentials(Credentials::new(u, p));
        }
        builder.build()
    };

    let mut last_err: Option<anyhow::Error> = None;
    for attempt in 1..=MAX_ATTEMPTS {
        let email = build_message()?; // re-build each attempt (Message is not Clone)
        match mailer.send(email).await.context("SMTP send failed") {
            Ok(_) => {
                tracing::info!(
                    to         = %to,
                    subject    = %subject,
                    smtp_host  = %smtp_host,
                    attempt    = attempt,
                    "email sent"
                );
                return Ok(());
            }
            Err(e) => {
                if is_permanent_error(&e) {
                    tracing::error!(error=%e, to=%to, "permanent SMTP error, not retrying");
                    return Err(e);
                }
                let delay_ms = 250u64 * 2u64.pow(attempt - 1); // 250ms, 500ms, 1s
                tracing::warn!(
                    attempt   = attempt,
                    max       = MAX_ATTEMPTS,
                    delay_ms  = delay_ms,
                    error     = %e,
                    to        = %to,
                    "transient SMTP error, retrying"
                );
                last_err = Some(e);
                if attempt < MAX_ATTEMPTS {
                    tokio::time::sleep(tokio::time::Duration::from_millis(delay_ms)).await;
                }
            }
        }
    }

    Err(last_err.unwrap_or_else(|| anyhow::anyhow!("SMTP send failed after {MAX_ATTEMPTS} attempts")))
}

// ─────────────────────────────────────────────────────────────────────────────
// Email templates
// ─────────────────────────────────────────────────────────────────────────────

fn invite_html(display_name: &str, activation_url: &str, invited_by: Option<&str>) -> String {
    let invited_by_line = match invited_by {
        Some(by) => format!(
            r#"<p style="color:#64748b;margin:0 0 20px">You were invited by <strong style="color:#e2e8f0">{}</strong>.</p>"#,
            by
        ),
        None => String::new(),
    };

    format!(
        r#"<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#0a1628;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif">
  <table width="100%" cellpadding="0" cellspacing="0" style="padding:48px 16px">
    <tr><td align="center">
      <table width="520" cellpadding="0" cellspacing="0"
             style="background:#111e35;border-radius:16px;border:1px solid #1e3a5f;overflow:hidden">

        <!-- Header -->
        <tr>
          <td style="padding:36px 40px 28px;border-bottom:1px solid #1e3a5f">
            <p style="margin:0;font-size:13px;font-weight:700;letter-spacing:2px;color:#00c896">
              NEXUS AI MDM
            </p>
          </td>
        </tr>

        <!-- Body -->
        <tr>
          <td style="padding:36px 40px">
            <h1 style="margin:0 0 12px;font-size:26px;font-weight:700;color:#f1f5f9;line-height:1.2">
              You've been invited
            </h1>
            <p style="color:#94a3b8;margin:0 0 24px;font-size:15px;line-height:1.6">
              Hi {display_name}, your Nexus AI MDM account is ready. Click the button below to
              set your password and activate your account.
            </p>
            {invited_by_line}
            <table cellpadding="0" cellspacing="0" style="margin:28px 0">
              <tr>
                <td style="border-radius:10px;background:#00c896">
                  <a href="{activation_url}"
                     style="display:inline-block;padding:14px 32px;font-size:15px;font-weight:600;
                            color:#0a1628;text-decoration:none;letter-spacing:0.2px">
                    Activate Account
                  </a>
                </td>
              </tr>
            </table>
            <p style="color:#64748b;font-size:13px;margin:0 0 8px">
              Or copy this link into your browser:
            </p>
            <p style="margin:0;word-break:break-all">
              <a href="{activation_url}"
                 style="color:#00c896;font-size:12px;text-decoration:none">{activation_url}</a>
            </p>
          </td>
        </tr>

        <!-- Footer -->
        <tr>
          <td style="padding:20px 40px;border-top:1px solid #1e3a5f">
            <p style="margin:0;font-size:12px;color:#475569;line-height:1.5">
              This link expires in 7 days. If you didn't expect this invitation, you can ignore
              this email.
            </p>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>"#,
        display_name    = display_name,
        activation_url  = activation_url,
        invited_by_line = invited_by_line,
    )
}

fn invite_plain(display_name: &str, activation_url: &str, invited_by: Option<&str>) -> String {
    let by_line = invited_by
        .map(|b| format!("Invited by: {}\n", b))
        .unwrap_or_default();

    format!(
        "Hi {display_name},\n\n\
         You've been invited to Nexus AI MDM.\n\
         {by_line}\n\
         Activate your account by visiting:\n{activation_url}\n\n\
         This link expires in 7 days.\n\n\
         — The Nexus AI MDM Team"
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// Password reset email
// ─────────────────────────────────────────────────────────────────────────────

/// Send a password-reset email with a one-time link.
/// Gracefully no-ops (logs only) when SMTP_HOST is not configured.
pub async fn send_password_reset_email(
    to:        &str,
    name:      &str,
    reset_url: &str,
) -> Result<()> {
    let subject = "Reset your Nexus AI MDM password".to_string();
    let html    = reset_html(name, reset_url);
    let plain   = reset_plain(name, reset_url);
    send(to, &subject, &html, &plain).await
}

fn reset_html(name: &str, reset_url: &str) -> String {
    format!(
        r#"<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#0a1628;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif">
  <table width="100%" cellpadding="0" cellspacing="0" style="padding:48px 16px">
    <tr><td align="center">
      <table width="520" cellpadding="0" cellspacing="0"
             style="background:#111e35;border-radius:16px;border:1px solid #1e3a5f;overflow:hidden">

        <!-- Header -->
        <tr>
          <td style="padding:36px 40px 28px;border-bottom:1px solid #1e3a5f">
            <p style="margin:0;font-size:13px;font-weight:700;letter-spacing:2px;color:#00c896">
              NEXUS AI MDM
            </p>
          </td>
        </tr>

        <!-- Body -->
        <tr>
          <td style="padding:36px 40px">
            <h1 style="margin:0 0 12px;font-size:26px;font-weight:700;color:#f1f5f9;line-height:1.2">
              Reset your password
            </h1>
            <p style="color:#94a3b8;margin:0 0 24px;font-size:15px;line-height:1.6">
              Hi {name}, we received a request to reset your Nexus AI MDM password.
              Click the button below to choose a new password.
            </p>
            <table cellpadding="0" cellspacing="0" style="margin:28px 0">
              <tr>
                <td style="border-radius:10px;background:#00c896">
                  <a href="{reset_url}"
                     style="display:inline-block;padding:14px 32px;font-size:15px;font-weight:600;
                            color:#0a1628;text-decoration:none;letter-spacing:0.2px">
                    Reset Password
                  </a>
                </td>
              </tr>
            </table>
            <p style="color:#64748b;font-size:13px;margin:0 0 8px">
              Or copy this link into your browser:
            </p>
            <p style="margin:0;word-break:break-all">
              <a href="{reset_url}"
                 style="color:#00c896;font-size:12px;text-decoration:none">{reset_url}</a>
            </p>
          </td>
        </tr>

        <!-- Footer -->
        <tr>
          <td style="padding:20px 40px;border-top:1px solid #1e3a5f">
            <p style="margin:0;font-size:12px;color:#475569;line-height:1.5">
              This link expires in 1 hour. If you didn't request a password reset,
              you can safely ignore this email — your password won't change.
            </p>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>"#,
        name      = name,
        reset_url = reset_url,
    )
}

fn reset_plain(name: &str, reset_url: &str) -> String {
    format!(
        "Hi {name},\n\n\
         We received a request to reset your Nexus AI MDM password.\n\n\
         Reset your password by visiting:\n{reset_url}\n\n\
         This link expires in 1 hour.\n\
         If you didn't request this, you can safely ignore this email.\n\n\
         — The Nexus AI MDM Team"
    )
}
