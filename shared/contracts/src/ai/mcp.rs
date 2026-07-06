use serde::{Deserialize, Serialize};

//
// ========================================
// MCP REQUEST
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct MCPRequest {

    /// Tenant UUID — can be supplied by caller or injected by the gateway from
    /// the validated X-Tenant-ID header.
    pub tenant_id: Option<String>,

    /// Authenticated user identity — injected by the gateway from the JWT.
    /// Never trust a caller-supplied value; the gateway overwrites it.
    pub user_id: Option<String>,

    /// Free-form user query. Also accepted as `message` from the Flutter UI.
    #[serde(alias = "message")]
    pub prompt: Option<String>,

    pub correlation_id: Option<String>,

    /// Optional explicit tool name for structured MCP calls.
    pub tool: Option<String>,

    /// Tool arguments (for structured calls).
    pub args: Option<serde_json::Value>,

    /// Response format hint: "auto" (server detects from query) | "prose" | "table".
    pub response_format: Option<String>,
}

//
// ========================================
// MCP RESPONSE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MCPResponse {

    pub success: bool,

    pub response: String,

    pub correlation_id: String,
}