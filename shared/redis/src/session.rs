use std::time::Duration;

use anyhow::Result;
use chrono::{DateTime, Utc};
use deadpool_redis::Pool;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

const SESSION_TTL_SECS: u64 = 28_800; // 8 hours

/// Data stored in a user session.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionData {
    pub session_id:  String,
    pub user_id:     Uuid,
    pub tenant_id:   Uuid,
    pub email:       String,
    pub display_name: String,
    pub role:        String,
    pub created_at:  DateTime<Utc>,
    pub last_seen_at: DateTime<Utc>,
    pub ip_address:  Option<String>,
    pub user_agent:  Option<String>,
}

impl SessionData {
    pub fn new(
        user_id:      Uuid,
        tenant_id:    Uuid,
        email:        impl Into<String>,
        display_name: impl Into<String>,
        role:         impl Into<String>,
    ) -> Self {
        let now = Utc::now();
        Self {
            session_id:   Uuid::new_v4().to_string(),
            user_id,
            tenant_id,
            email:        email.into(),
            display_name: display_name.into(),
            role:         role.into(),
            created_at:   now,
            last_seen_at: now,
            ip_address:   None,
            user_agent:   None,
        }
    }

    pub fn is_admin(&self) -> bool    { self.role == "admin" }
    pub fn is_steward(&self) -> bool  { self.role == "steward" || self.is_admin() }
    pub fn is_analyst(&self) -> bool  { self.role == "analyst" || self.is_steward() }
}

/// Redis-backed session store.
///
/// Session keys: `{prefix}:session:{session_id}`
/// Reverse lookup: `{prefix}:user_session:{user_id}` → session_id
#[derive(Clone)]
pub struct SessionStore {
    pool:   Pool,
    prefix: String,
    ttl:    Duration,
}

impl SessionStore {
    pub fn new(pool: Pool, prefix: impl Into<String>) -> Self {
        Self {
            pool,
            prefix: prefix.into(),
            ttl: Duration::from_secs(SESSION_TTL_SECS),
        }
    }

    pub fn with_ttl(mut self, ttl: Duration) -> Self {
        self.ttl = ttl;
        self
    }

    /// Persist a new session; returns the session_id.
    pub async fn create(&self, mut data: SessionData) -> Result<String> {
        data.last_seen_at = Utc::now();
        let session_id = data.session_id.clone();
        let user_id    = data.user_id;

        let session_key  = self.session_key(&session_id);
        let user_key     = self.user_session_key(user_id);

        let json = serde_json::to_string(&data)?;
        let mut conn = self.pool.get().await?;

        // Store session data with TTL
        let _: () = conn.set_ex(&session_key, &json, self.ttl.as_secs()).await?;
        // Reverse index: user → session (allows invalidating all sessions for a user)
        let _: () = conn.set_ex(&user_key, &session_id, self.ttl.as_secs()).await?;

        Ok(session_id)
    }

    /// Fetch and refresh the TTL (sliding expiry).
    pub async fn get(&self, session_id: &str) -> Result<Option<SessionData>> {
        let key = self.session_key(session_id);
        let mut conn = self.pool.get().await?;

        let raw: Option<String> = conn.get(&key).await?;
        match raw {
            None => Ok(None),
            Some(s) => {
                let mut data: SessionData = serde_json::from_str(&s)?;
                data.last_seen_at = Utc::now();

                // Refresh TTL (sliding window)
                let updated = serde_json::to_string(&data)?;
                let _: () = conn.set_ex(&key, updated, self.ttl.as_secs()).await?;

                Ok(Some(data))
            }
        }
    }

    /// Invalidate a specific session.
    pub async fn invalidate(&self, session_id: &str) -> Result<()> {
        let key = self.session_key(session_id);
        let mut conn = self.pool.get().await?;
        let _: () = conn.del(&key).await?;
        Ok(())
    }

    /// Invalidate all sessions for a user (logout everywhere).
    pub async fn invalidate_user(&self, user_id: Uuid) -> Result<()> {
        let user_key = self.user_session_key(user_id);
        let mut conn = self.pool.get().await?;

        let session_id: Option<String> = conn.get(&user_key).await?;
        if let Some(sid) = session_id {
            let session_key = self.session_key(&sid);
            let _: () = conn.del(&[&session_key, &user_key]).await?;
        }

        Ok(())
    }

    /// Check whether a session is valid without refreshing TTL.
    pub async fn exists(&self, session_id: &str) -> Result<bool> {
        let key = self.session_key(session_id);
        let mut conn = self.pool.get().await?;
        let exists: bool = conn.exists(&key).await?;
        Ok(exists)
    }

    fn session_key(&self, session_id: &str) -> String {
        format!("{}:session:{}", self.prefix, session_id)
    }

    fn user_session_key(&self, user_id: Uuid) -> String {
        format!("{}:user_session:{}", self.prefix, user_id)
    }
}
