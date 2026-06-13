use reqwest::{
    header::{
        HeaderMap,
        HeaderName,
        HeaderValue,
        AUTHORIZATION,
        CONTENT_TYPE,
    },
    Client,
};

use serde_json::Value;

use std::{
    collections::HashMap,
    time::Duration,
};

use uuid::Uuid;

//
// =========================================
// 🌐 SHARED HTTP CLIENT
// =========================================
//

#[allow(dead_code)]
fn http_client() -> Client {

    Client::builder()

        // =================================
        // CONNECTION POOL
        // =================================
        .pool_max_idle_per_host(20)

        // =================================
        // TIMEOUTS
        // =================================
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(30))

        // =================================
        // TCP
        // =================================
        .tcp_keepalive(Duration::from_secs(60))

        // =================================
        // BUILD
        // =================================
        .build()
        .expect("failed to build reqwest client")
}

//
// =========================================
// 🧾 PROXY HEADERS
// =========================================
//

#[allow(dead_code)]
#[derive(Default, Clone)]
pub struct ProxyHeaders {

    pub authorization: Option<String>,

    pub tenant_id: Option<String>,

    pub user_id: Option<String>,

    pub user_role: Option<String>,

    pub correlation_id: Option<String>,

    pub extra: HashMap<String, String>,
}

impl ProxyHeaders {

    #[allow(dead_code)]
    pub fn to_headers(&self) -> HeaderMap {

        let mut headers = HeaderMap::new();

        // ================================
        // AUTHORIZATION
        // ================================
        if let Some(auth) = &self.authorization {

            if let Ok(value) = HeaderValue::from_str(auth) {
                headers.insert(AUTHORIZATION, value);
            }
        }

        // ================================
        // TENANT
        // ================================
        insert_header(
            &mut headers,
            "x-tenant-id",
            self.tenant_id.as_deref(),
        );

        // ================================
        // USER
        // ================================
        insert_header(
            &mut headers,
            "x-user-id",
            self.user_id.as_deref(),
        );

        // ================================
        // ROLE
        // ================================
        insert_header(
            &mut headers,
            "x-user-role",
            self.user_role.as_deref(),
        );

        // ================================
        // CORRELATION ID
        // ================================
        insert_header(
            &mut headers,
            "x-correlation-id",
            self.correlation_id.as_deref(),
        );

        // ================================
        // EXTRA
        // ================================
        for (k, v) in &self.extra {

            if let (
                Ok(name),
                Ok(value),
            ) = (
                HeaderName::from_bytes(k.as_bytes()),
                HeaderValue::from_str(v),
            ) {
                headers.insert(name, value);
            }
        }

        headers.insert(
            CONTENT_TYPE,
            HeaderValue::from_static("application/json"),
        );

        headers
    }
}

//
// =========================================
// 🧾 HEADER HELPER
// =========================================
//

#[allow(dead_code)]
fn insert_header(
    headers: &mut HeaderMap,
    key: &str,
    value: Option<&str>,
) {

    if let Some(v) = value {

        if let Ok(header_value) = HeaderValue::from_str(v) {

            if let Ok(header_name) =
                HeaderName::from_bytes(key.as_bytes())
            {
                headers.insert(header_name, header_value);
            }
        }
    }
}

//
// =========================================
// 🚀 FORWARD POST
// =========================================
//

#[allow(dead_code)]
pub async fn forward_post(
    url: &str,
    body: Value,
    proxy_headers: Option<ProxyHeaders>,
) -> Result<Value, String> {

    let correlation_id = Uuid::new_v4();

    let client = http_client();

    // =====================================
    // HEADERS
    // =====================================
    let headers = proxy_headers
        .unwrap_or_default()
        .to_headers();

    // =====================================
    // REQUEST
    // =====================================
    let response = client
        .post(url)
        .headers(headers)
        .json(&body)
        .send()
        .await
        .map_err(|e| {
            format!(
                "[{}] upstream request failed: {}",
                correlation_id,
                e
            )
        })?;

    let status = response.status();

    // =====================================
    // SUCCESS
    // =====================================
    if status.is_success() {

        return response
            .json::<Value>()
            .await
            .map_err(|e| {
                format!(
                    "[{}] invalid upstream json: {}",
                    correlation_id,
                    e
                )
            });
    }

    // =====================================
    // ERROR BODY
    // =====================================
    let error_body = response
        .text()
        .await
        .unwrap_or_else(|_| "unknown upstream error".into());

    Err(format!(
        "[{}] upstream returned {}: {}",
        correlation_id,
        status,
        error_body
    ))
}

//
// =========================================
// 🚀 FORWARD GET
// =========================================
//

#[allow(dead_code)]
pub async fn forward_get(
    url: &str,
    proxy_headers: Option<ProxyHeaders>,
) -> Result<Value, String> {

    let correlation_id = Uuid::new_v4();

    let client = http_client();

    let headers = proxy_headers
        .unwrap_or_default()
        .to_headers();

    let response = client
        .get(url)
        .headers(headers)
        .send()
        .await
        .map_err(|e| {
            format!(
                "[{}] upstream request failed: {}",
                correlation_id,
                e
            )
        })?;

    let status = response.status();

    if status.is_success() {

        return response
            .json::<Value>()
            .await
            .map_err(|e| {
                format!(
                    "[{}] invalid upstream json: {}",
                    correlation_id,
                    e
                )
            });
    }

    let error_body = response
        .text()
        .await
        .unwrap_or_else(|_| "unknown upstream error".into());

    Err(format!(
        "[{}] upstream returned {}: {}",
        correlation_id,
        status,
        error_body
    ))
}