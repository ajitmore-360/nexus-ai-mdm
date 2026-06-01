use serde::{Deserialize, Serialize};

//
// ========================================
// TOOL REQUEST
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolRequest {

    pub tool_name: String,

    pub arguments: serde_json::Value,
}

//
// ========================================
// TOOL RESPONSE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolResponse {

    pub success: bool,

    pub result: serde_json::Value,

    pub error: Option<String>,
}