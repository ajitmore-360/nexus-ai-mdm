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
    /// Business administrator — manages org setup (users, schemas, policies) and has
    /// governance oversight of data (approve/reject matches, view all records).
    /// Explicitly excluded from direct entity data entry and merge operations.
    #[serde(rename = "business_admin")]
    BusinessAdmin,
    /// Tenant administrator — full access within the tenant.
    Admin,
    /// Platform super-admin — cross-tenant access (internal use only).
    SuperAdmin,
}

impl Role {
    /// True for roles that can create and edit entity records directly.
    /// BusinessAdmin is excluded — they govern data but do not perform data entry.
    pub fn can_write(&self) -> bool {
        matches!(self, Role::Steward | Role::Admin | Role::SuperAdmin)
    }

    /// True for roles that can approve or reject match candidates.
    /// BusinessAdmin has approval authority as part of data-governance oversight.
    pub fn can_approve(&self) -> bool {
        matches!(self, Role::Steward | Role::BusinessAdmin | Role::Admin | Role::SuperAdmin)
    }

    /// True for roles that can administer tenant configuration (users, schemas, policies).
    pub fn can_admin(&self) -> bool {
        matches!(self, Role::BusinessAdmin | Role::Admin | Role::SuperAdmin)
    }

    pub fn can_read(&self) -> bool {
        true // all roles can read
    }
}

impl std::fmt::Display for Role {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            Role::Viewer        => "viewer",
            Role::Analyst       => "analyst",
            Role::Steward       => "steward",
            Role::BusinessAdmin => "business_admin",
            Role::Admin         => "admin",
            Role::SuperAdmin    => "super_admin",
        };
        write!(f, "{}", s)
    }
}

impl std::str::FromStr for Role {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "viewer"         => Ok(Role::Viewer),
            "analyst"        => Ok(Role::Analyst),
            "steward"        => Ok(Role::Steward),
            "business_admin" => Ok(Role::BusinessAdmin),
            "admin"          => Ok(Role::Admin),
            "super_admin"    => Ok(Role::SuperAdmin),
            other => Err(anyhow::anyhow!("unknown role: {}", other)),
        }
    }
}
