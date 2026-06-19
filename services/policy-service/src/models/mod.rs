use chrono::{
    DateTime,
    Utc,
};

use serde::{
    Deserialize,
    Serialize,
};

use uuid::Uuid;

//
// ========================================
// POLICY RULE TYPE
// ========================================
//

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PolicyRuleType {

    /// Mask specific fields for certain roles/contexts
    FieldMask,

    /// Override survivorship logic for specific fields
    SurvivorshipOverride,

    /// Control access to entities or operations
    AccessControl,

    /// Govern retention and deletion windows
    DataRetention,

    /// GDPR/privacy consent enforcement
    GdprConsent,

    /// Enforce mandatory field presence
    MandatoryField,

    /// Business validation rules
    ValidationRule,
}

impl std::fmt::Display for PolicyRuleType {

    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            PolicyRuleType::FieldMask            => "field_mask",
            PolicyRuleType::SurvivorshipOverride => "survivorship_override",
            PolicyRuleType::AccessControl        => "access_control",
            PolicyRuleType::DataRetention        => "data_retention",
            PolicyRuleType::GdprConsent          => "gdpr_consent",
            PolicyRuleType::MandatoryField       => "mandatory_field",
            PolicyRuleType::ValidationRule       => "validation_rule",
        };
        write!(f, "{}", s)
    }
}

impl std::str::FromStr for PolicyRuleType {

    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "field_mask"             => Ok(PolicyRuleType::FieldMask),
            "survivorship_override"  => Ok(PolicyRuleType::SurvivorshipOverride),
            "access_control"         => Ok(PolicyRuleType::AccessControl),
            "data_retention"         => Ok(PolicyRuleType::DataRetention),
            "gdpr_consent"           => Ok(PolicyRuleType::GdprConsent),
            "mandatory_field"        => Ok(PolicyRuleType::MandatoryField),
            "validation_rule"        => Ok(PolicyRuleType::ValidationRule),
            other => Err(anyhow::anyhow!("Unknown PolicyRuleType: {}", other)),
        }
    }
}

//
// ========================================
// POLICY RULE STATUS
// ========================================
//

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PolicyRuleStatus {

    Active,

    Inactive,
}

impl std::fmt::Display for PolicyRuleStatus {

    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PolicyRuleStatus::Active   => write!(f, "active"),
            PolicyRuleStatus::Inactive => write!(f, "inactive"),
        }
    }
}

impl std::str::FromStr for PolicyRuleStatus {

    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "active"   => Ok(PolicyRuleStatus::Active),
            "inactive" => Ok(PolicyRuleStatus::Inactive),
            other      => Err(anyhow::anyhow!("Unknown PolicyRuleStatus: {}", other)),
        }
    }
}

//
// ========================================
// POLICY RULE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolicyRule {

    /// Unique rule identifier
    pub rule_id: Uuid,

    /// Tenant this rule belongs to
    pub tenant_id: Uuid,

    /// Human-readable rule name
    pub name: String,

    /// Optional description
    pub description: Option<String>,

    /// Semantic category of this rule
    pub rule_type: PolicyRuleType,

    /// Entity type this rule applies to (None = all entity types)
    pub entity_type: Option<String>,

    /// Specific field this rule governs (None = entity-level)
    pub field_name: Option<String>,

    /// Rego policy text or path reference evaluated via OPA
    pub rego_policy: String,

    /// Higher priority rules are evaluated first (ascending)
    pub priority: i32,

    /// Active/inactive status
    pub status: PolicyRuleStatus,

    /// When this rule was created
    pub created_at: DateTime<Utc>,

    /// When this rule was last updated
    pub updated_at: DateTime<Utc>,
}

//
// ========================================
// POLICY OPERATION
// ========================================
//

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PolicyOperation {

    Read,

    Write,

    Merge,

    Distribute,

    Delete,

    Export,
}

impl std::fmt::Display for PolicyOperation {

    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            PolicyOperation::Read       => "read",
            PolicyOperation::Write      => "write",
            PolicyOperation::Merge      => "merge",
            PolicyOperation::Distribute => "distribute",
            PolicyOperation::Delete     => "delete",
            PolicyOperation::Export     => "export",
        };
        write!(f, "{}", s)
    }
}

//
// ========================================
// POLICY CONTEXT
// ========================================
// This is the input that callers supply when asking
// "is this operation allowed for this entity?"
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolicyContext {

    /// Tenant performing the operation
    pub tenant_id: Uuid,

    /// Authenticated user (None for system/service calls)
    pub user_id: Option<Uuid>,

    /// Entity type being operated on
    pub entity_type: String,

    /// Operation being requested
    pub operation: PolicyOperation,

    /// The full entity payload (for field-level evaluation)
    pub entity: serde_json::Value,

    /// Role of the calling user (e.g. "admin", "analyst", "readonly")
    pub user_role: Option<String>,

    /// Target system for distribution operations
    pub target_system: Option<String>,

    /// Optional metadata for rule context
    pub attributes: Option<serde_json::Value>,
}

//
// ========================================
// POLICY DECISION
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolicyDecision {

    /// Whether the operation is allowed
    pub allowed: bool,

    /// Human-readable reason for the decision
    pub reason: String,

    /// Fields that must be masked in the response
    pub masked_fields: Vec<String>,

    /// Fields that are required but missing
    pub required_fields: Vec<String>,

    /// Non-blocking policy warnings
    pub warnings: Vec<String>,

    /// Which rules contributed to this decision
    pub applied_rules: Vec<String>,
}

impl PolicyDecision {

    /// Construct a permissive (allow-all) decision, used for fail-open scenarios
    pub fn permissive(reason: impl Into<String>) -> Self {
        Self {
            allowed:        true,
            reason:         reason.into(),
            masked_fields:  vec![],
            required_fields: vec![],
            warnings:       vec![],
            applied_rules:  vec![],
        }
    }

    /// Construct a deny decision
    #[allow(dead_code)]
    pub fn deny(reason: impl Into<String>) -> Self {
        Self {
            allowed:        false,
            reason:         reason.into(),
            masked_fields:  vec![],
            required_fields: vec![],
            warnings:       vec![],
            applied_rules:  vec![],
        }
    }
}

//
// ========================================
// OPA WIRE TYPES
// ========================================
//

/// Wrapper sent as the POST body to OPA's /v1/data/{path}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpaInput {

    pub input: PolicyContext,
}

/// OPA /v1/data response envelope
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpaResponse {

    /// The evaluated result from OPA.
    /// May be absent when OPA returns an undefined result.
    pub result: Option<OpaResult>,
}

/// The structured result we expect inside OPA's response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpaResult {

    pub allowed: bool,

    #[serde(default)]
    pub reason: String,

    #[serde(default)]
    pub masked_fields: Vec<String>,

    #[serde(default)]
    pub required_fields: Vec<String>,

    #[serde(default)]
    pub warnings: Vec<String>,
}

//
// ========================================
// GDPR REQUEST TYPE
// ========================================
//

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GdprRequestType {

    /// Article 17 – Right to erasure
    Erasure,

    /// Article 15 – Right of access
    Access,

    /// Article 20 – Right to data portability
    Portability,
}

impl std::fmt::Display for GdprRequestType {

    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GdprRequestType::Erasure     => write!(f, "erasure"),
            GdprRequestType::Access      => write!(f, "access"),
            GdprRequestType::Portability => write!(f, "portability"),
        }
    }
}

//
// ========================================
// GDPR REQUEST
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GdprRequest {

    /// Tenant making the request
    pub tenant_id: Uuid,

    /// The data subject's entity ID to act upon
    pub subject_id: Uuid,

    /// Type of GDPR request
    pub request_type: GdprRequestType,

    /// When this request was submitted
    pub requested_at: DateTime<Utc>,

    /// Optional free-text reason for audit purposes
    pub reason: Option<String>,

    /// Who submitted this request
    pub requested_by: Option<String>,
}

//
// ========================================
// GDPR RESULT
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GdprResult {

    /// Subject whose data was acted upon
    pub subject_id: Uuid,

    /// Type of GDPR request completed
    pub request_type: GdprRequestType,

    /// Fields that were erased or anonymised
    pub fields_erased: Vec<String>,

    /// Total entity records affected
    pub records_affected: i64,

    /// When the operation completed
    pub completed_at: DateTime<Utc>,

    /// Audit record ID for compliance tracking
    pub audit_id: Uuid,
}

//
// ========================================
// EVALUATE MERGE REQUEST
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvaluateMergeRequest {

    pub tenant_id: Uuid,

    pub source: serde_json::Value,

    pub candidate: serde_json::Value,
}

//
// ========================================
// CREATE RULE REQUEST
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateRuleRequest {

    pub tenant_id: Uuid,

    pub name: String,

    pub description: Option<String>,

    pub rule_type: PolicyRuleType,

    pub entity_type: Option<String>,

    pub field_name: Option<String>,

    pub rego_policy: String,

    pub priority: Option<i32>,
}

//
// ========================================
// API RESPONSE WRAPPER
// ========================================
//

#[derive(Debug, Serialize, Deserialize)]
pub struct ApiResponse<T>
where
    T: Serialize,
{
    pub success: bool,

    pub data: Option<T>,

    pub error: Option<String>,
}

impl<T: Serialize> ApiResponse<T> {

    pub fn ok(data: T) -> Self {
        Self {
            success: true,
            data:    Some(data),
            error:   None,
        }
    }

    pub fn err(msg: impl Into<String>) -> Self {
        Self {
            success: false,
            data:    None,
            error:   Some(msg.into()),
        }
    }
}

//
// ========================================
// CONSENT TYPE
// ========================================
//

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConsentType {
    Marketing,
    Analytics,
    Profiling,
    ThirdPartyShare,
    AutomatedDecision,
    Research,
    /// Generic processing consent used when no specific type applies
    Processing,
}

impl std::fmt::Display for ConsentType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            ConsentType::Marketing          => "marketing",
            ConsentType::Analytics          => "analytics",
            ConsentType::Profiling          => "profiling",
            ConsentType::ThirdPartyShare    => "third_party_share",
            ConsentType::AutomatedDecision  => "automated_decision",
            ConsentType::Research           => "research",
            ConsentType::Processing         => "processing",
        };
        write!(f, "{}", s)
    }
}

impl std::str::FromStr for ConsentType {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "marketing"          => Ok(ConsentType::Marketing),
            "analytics"          => Ok(ConsentType::Analytics),
            "profiling"          => Ok(ConsentType::Profiling),
            "third_party_share"  => Ok(ConsentType::ThirdPartyShare),
            "automated_decision" => Ok(ConsentType::AutomatedDecision),
            "research"           => Ok(ConsentType::Research),
            "processing"         => Ok(ConsentType::Processing),
            other => Err(anyhow::anyhow!("Unknown ConsentType: {}", other)),
        }
    }
}

//
// ========================================
// CONSENT RECORD
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsentRecord {
    pub consent_id:    Uuid,
    pub tenant_id:     Uuid,
    pub entity_id:     Uuid,
    pub consent_type:  ConsentType,
    pub legal_basis:   String,
    pub consent_given: bool,
    pub purpose:       Option<String>,
    pub source:        Option<String>,
    pub granted_at:    Option<DateTime<Utc>>,
    pub withdrawn_at:  Option<DateTime<Utc>>,
    pub expires_at:    Option<DateTime<Utc>>,
    pub recorded_by:   Option<String>,
    pub metadata:      serde_json::Value,
    pub created_at:    DateTime<Utc>,
    pub updated_at:    DateTime<Utc>,
}

//
// ========================================
// RECORD CONSENT REQUEST
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecordConsentRequest {
    pub tenant_id:     Uuid,
    pub entity_id:     Uuid,
    pub consent_type:  ConsentType,
    pub legal_basis:   Option<String>,
    pub consent_given: bool,
    pub purpose:       Option<String>,
    pub source:        Option<String>,
    pub expires_at:    Option<DateTime<Utc>>,
    pub recorded_by:   Option<String>,
    pub metadata:      Option<serde_json::Value>,
}

//
// ========================================
// WITHDRAW CONSENT QUERY
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WithdrawConsentQuery {
    pub tenant_id: Uuid,
}

#[cfg(test)]
mod tests {

    use super::*;

    #[test]
    fn test_policy_rule_type_roundtrip() {
        let types = vec![
            PolicyRuleType::FieldMask,
            PolicyRuleType::SurvivorshipOverride,
            PolicyRuleType::AccessControl,
            PolicyRuleType::DataRetention,
            PolicyRuleType::GdprConsent,
            PolicyRuleType::MandatoryField,
            PolicyRuleType::ValidationRule,
        ];

        for rt in &types {
            let s = rt.to_string();
            let parsed: PolicyRuleType = s.parse().expect("roundtrip failed");
            assert_eq!(rt, &parsed, "roundtrip failed for {:?}", rt);
        }
    }

    #[test]
    fn test_policy_decision_permissive() {
        let d = PolicyDecision::permissive("fail-open");
        assert!(d.allowed);
        assert!(d.masked_fields.is_empty());
    }

    #[test]
    fn test_policy_decision_deny() {
        let d = PolicyDecision::deny("access denied");
        assert!(!d.allowed);
        assert_eq!(d.reason, "access denied");
    }

    #[test]
    fn test_opa_input_serializes() {
        let ctx = PolicyContext {
            tenant_id:     Uuid::new_v4(),
            user_id:       None,
            entity_type:   "customer".into(),
            operation:     PolicyOperation::Read,
            entity:        serde_json::json!({}),
            user_role:     Some("analyst".into()),
            target_system: None,
            attributes:    None,
        };
        let input = OpaInput { input: ctx };
        let json = serde_json::to_string(&input).expect("serialization failed");
        assert!(json.contains("\"input\""));
    }

    #[test]
    fn test_gdpr_request_type_display() {
        assert_eq!(GdprRequestType::Erasure.to_string(),     "erasure");
        assert_eq!(GdprRequestType::Access.to_string(),      "access");
        assert_eq!(GdprRequestType::Portability.to_string(), "portability");
    }
}
