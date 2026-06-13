//! Experian business credit enrichment provider.
//!
//! Mock mode derives all values deterministically from the entity name hash
//! so unit tests remain stable across runs.  Real mode calls the Experian
//! Business Information Services REST API.

use std::collections::HashMap;

use async_trait::async_trait;
use chrono::Utc;
use serde_json::{json, Value};

use super::{attr_str, name_hash, EnrichmentData, EnrichmentProvider, EnrichmentRequest};

// ── risk tier labels ──────────────────────────────────────────────────────────
const RISK_RATINGS: &[&str] = &["Low", "Low-Medium", "Medium", "Medium-High", "High"];

/// Experian provider — consumer/business credit data for Customer entities.
pub struct ExperianProvider {
    mock_mode: bool,
    api_key:   Option<String>,
    client:    reqwest::Client,
}

impl ExperianProvider {
    pub fn new(mock_mode: bool, api_key: Option<String>) -> Self {
        Self {
            mock_mode,
            api_key,
            client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(10))
                .build()
                .expect("failed to build reqwest client"),
        }
    }

    // ── mock implementation ───────────────────────────────────────────────────

    fn mock_enrich(&self, req: &EnrichmentRequest) -> EnrichmentData {
        let name = attr_str(&req.attributes, "name")
            .or_else(|| attr_str(&req.attributes, "company_name"))
            .or_else(|| attr_str(&req.attributes, "legal_name"))
            .unwrap_or("unknown");

        let h = name_hash(name);

        // Credit score: 300 – 850  (FICO-range)
        let credit_score: u64 = 300 + (h % 551);

        // Risk rating driven by credit score band
        let risk_idx = match credit_score {
            750..=850 => 0, // Low
            680..=749 => 1, // Low-Medium
            620..=679 => 2, // Medium
            560..=619 => 3, // Medium-High
            _         => 4, // High
        };
        let risk_rating = RISK_RATINGS[risk_idx];

        // Payment index: 0 – 100 (higher = pays faster)
        let payment_index: u64 = (h >> 3) % 101;

        // Years in business: 1 – 80
        let years_in_business: u64 = 1 + (h % 80);

        // Intelliscore Plus: 1 – 100
        let intelliscore: u64 = 1 + (h % 100);

        // FSR (Financial Stability Risk) score: 1 – 5 (1 = lowest risk)
        let fsr_score: u64 = 1 + (h % 5);

        // Derogatory legal count: 0 – 5
        let derogatory_count: u64 = (h >> 10) % 6;

        let mut fields: HashMap<String, Value> = HashMap::new();
        fields.insert("experian_credit_score".to_string(),     json!(credit_score));
        fields.insert("experian_risk_rating".to_string(),      json!(risk_rating));
        fields.insert("experian_payment_index".to_string(),    json!(payment_index));
        fields.insert("experian_years_in_business".to_string(), json!(years_in_business));
        fields.insert("experian_intelliscore".to_string(),     json!(intelliscore));
        fields.insert("experian_fsr_score".to_string(),        json!(fsr_score));
        fields.insert("experian_derogatory_count".to_string(), json!(derogatory_count));
        fields.insert("experian_enriched_by".to_string(),      json!("mock"));

        // Confidence is higher for well-known names (longer names correlate loosely)
        let confidence = if name.len() > 8 { 0.88 } else { 0.70 };

        EnrichmentData {
            provider:    self.name().to_string(),
            fields,
            confidence,
            enriched_at: Utc::now(),
        }
    }

    // ── real API call ─────────────────────────────────────────────────────────

    async fn real_enrich(&self, req: &EnrichmentRequest) -> anyhow::Result<EnrichmentData> {
        let api_key = self.api_key.as_deref().ok_or_else(|| {
            anyhow::anyhow!("EXPERIAN_API_KEY is required when mock_mode = false")
        })?;

        let name    = attr_str(&req.attributes, "name").unwrap_or("");
        let street  = attr_str(&req.attributes, "address_street").unwrap_or("");
        let city    = attr_str(&req.attributes, "address_city").unwrap_or("");
        let state   = attr_str(&req.attributes, "address_state").unwrap_or("");
        let zip     = attr_str(&req.attributes, "address_zip").unwrap_or("");

        let payload = json!({
            "name":    name,
            "street":  street,
            "city":    city,
            "state":   state,
            "zip":     zip,
            "subcode": "0517614",
        });

        let resp = self
            .client
            .post("https://us-api.experian.com/businessinformation/businesses/v1/search")
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&payload)
            .send()
            .await?
            .error_for_status()?
            .json::<serde_json::Value>()
            .await?;

        let bin = resp
            .pointer("/results/0/bin")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow::anyhow!("Experian: no BIN returned for entity"))?;

        // Fetch credit profile
        let profile = self
            .client
            .get(format!(
                "https://us-api.experian.com/businessinformation/businesses/v1/{}/creditreport",
                bin
            ))
            .header("Authorization", format!("Bearer {}", api_key))
            .send()
            .await?
            .error_for_status()?
            .json::<serde_json::Value>()
            .await?;

        let mut fields: HashMap<String, Value> = HashMap::new();
        fields.insert("experian_bin".to_string(),
            json!(bin));
        fields.insert("experian_credit_score".to_string(),
            json!(profile.pointer("/intelliscore/score").cloned().unwrap_or(Value::Null)));
        fields.insert("experian_risk_rating".to_string(),
            json!(profile.pointer("/intelliscore/riskClass/definition").cloned().unwrap_or(Value::Null)));
        fields.insert("experian_payment_index".to_string(),
            json!(profile.pointer("/paymentTrend/currentPaydex").cloned().unwrap_or(Value::Null)));
        fields.insert("experian_fsr_score".to_string(),
            json!(profile.pointer("/fsrScore/score").cloned().unwrap_or(Value::Null)));
        fields.insert("experian_enriched_by".to_string(), json!("experian_api"));

        Ok(EnrichmentData {
            provider:    self.name().to_string(),
            fields,
            confidence:  0.95,
            enriched_at: Utc::now(),
        })
    }
}

#[async_trait]
impl EnrichmentProvider for ExperianProvider {
    fn name(&self) -> &str {
        "Experian"
    }

    /// Experian only enriches Customer entities (consumer/business credit).
    fn applies_to(&self, req: &EnrichmentRequest) -> bool {
        req.entity_type == "Customer"
    }

    async fn enrich(&self, req: &EnrichmentRequest) -> anyhow::Result<EnrichmentData> {
        if self.mock_mode {
            Ok(self.mock_enrich(req))
        } else {
            self.real_enrich(req).await
        }
    }
}

// ── tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    fn make_req(name: &str) -> EnrichmentRequest {
        EnrichmentRequest {
            entity_id:   Uuid::new_v4(),
            tenant_id:   Uuid::new_v4(),
            entity_type: "Customer".to_string(),
            attributes:  serde_json::json!({ "name": name }),
        }
    }

    #[test]
    fn test_mock_is_deterministic() {
        let p  = ExperianProvider::new(true, None);
        let r1 = p.mock_enrich(&make_req("Globex Corp"));
        let r2 = p.mock_enrich(&make_req("Globex Corp"));

        assert_eq!(r1.fields["experian_credit_score"],     r2.fields["experian_credit_score"]);
        assert_eq!(r1.fields["experian_risk_rating"],      r2.fields["experian_risk_rating"]);
        assert_eq!(r1.fields["experian_payment_index"],    r2.fields["experian_payment_index"]);
        assert_eq!(r1.fields["experian_years_in_business"], r2.fields["experian_years_in_business"]);
    }

    #[test]
    fn test_credit_score_range() {
        let p      = ExperianProvider::new(true, None);
        let result = p.mock_enrich(&make_req("TestBiz Inc"));
        let score  = result.fields["experian_credit_score"]
            .as_u64()
            .expect("credit_score should be a number");
        assert!((300..=850).contains(&score), "score {} out of 300–850 range", score);
    }

    #[test]
    fn test_risk_rating_valid() {
        let p      = ExperianProvider::new(true, None);
        let result = p.mock_enrich(&make_req("RiskyBiz"));
        let rating = result.fields["experian_risk_rating"]
            .as_str()
            .expect("risk_rating should be a string");
        assert!(
            RISK_RATINGS.contains(&rating),
            "risk_rating '{}' not in allowed set",
            rating
        );
    }

    #[test]
    fn test_payment_index_range() {
        let p      = ExperianProvider::new(true, None);
        let result = p.mock_enrich(&make_req("PayCo LLC"));
        let idx    = result.fields["experian_payment_index"]
            .as_u64()
            .expect("payment_index should be a number");
        assert!((0..=100).contains(&idx));
    }

    #[test]
    fn test_years_in_business_positive() {
        let p      = ExperianProvider::new(true, None);
        let result = p.mock_enrich(&make_req("OldBiz Partners"));
        let years  = result.fields["experian_years_in_business"]
            .as_u64()
            .expect("years_in_business should be a number");
        assert!(years >= 1 && years <= 80);
    }

    #[test]
    fn test_risk_consistent_with_score() {
        let p      = ExperianProvider::new(true, None);
        // Use a name whose hash reliably lands in the 750+ range
        // We test the invariant: if score >= 750 → risk = "Low"
        // (we don't know the actual score so just verify the rating lookup
        //  table is applied correctly by testing many names)
        for name in &["Alpha", "Beta Corp", "Gamma LLC", "Delta Inc", "Epsilon"] {
            let result = p.mock_enrich(&make_req(name));
            let score  = result.fields["experian_credit_score"].as_u64().unwrap();
            let rating = result.fields["experian_risk_rating"].as_str().unwrap();

            let expected_idx = match score {
                750..=850 => 0,
                680..=749 => 1,
                620..=679 => 2,
                560..=619 => 3,
                _         => 4,
            };
            assert_eq!(rating, RISK_RATINGS[expected_idx]);
        }
    }

    #[test]
    fn test_only_applies_to_customer() {
        let p = ExperianProvider::new(true, None);

        let customer = EnrichmentRequest {
            entity_id:   Uuid::new_v4(),
            tenant_id:   Uuid::new_v4(),
            entity_type: "Customer".to_string(),
            attributes:  serde_json::json!({}),
        };
        assert!(p.applies_to(&customer));

        for t in &["Vendor", "Location", "Product", "Employee"] {
            let req = EnrichmentRequest {
                entity_type: t.to_string(),
                ..customer.clone()
            };
            assert!(!p.applies_to(&req), "should not apply to {}", t);
        }
    }
}
