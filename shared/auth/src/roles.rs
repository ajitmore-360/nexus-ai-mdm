use serde::{Deserialize, Serialize};

/// Platform roles in ascending privilege order.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    /// Read-only access — can view entities and golden records.
    Viewer,
    /// Data analyst — can run match jobs and view all analytics.
    Analyst,
    /// Data steward — can review, approve/reject merges, edit entities.
    Steward,
    /// Tenant administrator — full access within the tenant.
    Admin,
    /// Platform super-admin — cross-tenant access (internal use only).
    SuperAdmin,
}

impl Role {
    pub fn can_write(&self) -> bool {
        *self >= Role::Steward
    }

    pub fn can_admin(&self) -> bool {
        *self >= Role::Admin
    }

    pub fn can_read(&self) -> bool {
        true // all roles can read
    }
}

impl std::fmt::Display for Role {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            Role::Viewer     => "viewer",
            Role::Analyst    => "analyst",
            Role::Steward    => "steward",
            Role::Admin      => "admin",
            Role::SuperAdmin => "super_admin",
        };
        write!(f, "{}", s)
    }
}

impl std::str::FromStr for Role {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "viewer"      => Ok(Role::Viewer),
            "analyst"     => Ok(Role::Analyst),
            "steward"     => Ok(Role::Steward),
            "admin"       => Ok(Role::Admin),
            "super_admin" => Ok(Role::SuperAdmin),
            other => Err(anyhow::anyhow!("unknown role: {}", other)),
        }
    }
}
