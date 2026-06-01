use serde::{Deserialize, Serialize};

//
// ========================================
// MCP REQUEST
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MCPRequest {

    pub tenant_id: String,

    pub user_id: String,

    pub prompt: String,

    pub correlation_id: String,
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