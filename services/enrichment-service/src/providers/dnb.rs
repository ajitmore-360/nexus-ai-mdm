//! Dun & Bradstreet enrichment provider.
//!
//! In mock mode all values are generated deterministically from the entity's
//! name hash so tests get stable, predictable data.  Real mode POSTs to the
//! D&B Direct+ REST API.

use std::collections::HashMap;

use async_trait::async_trait;
use chrono::Utc;
use serde_json::{json, Value};

use super::{attr_str, name_hash, EnrichmentData, EnrichmentProvider, EnrichmentRequest};

// ── credit ratings cycle ──────────────────────────────────────────────────────
const CREDIT_RATINGS: &[&str] = &["A", "A-", "B+", "B", "B-", "C+", "C", "D"];

// ── SIC codes sample (realistic subset) ──────────────────────────────────────
const SIC_CODES: &[&str] = &[
    "5045", "7372", "6159", "5122", "3674",
    "2836", "3825", "4813", "5065", "7374",
    "3559", "6411", "5047", "3841", "7371",
];

/// D&B provider — returns firmographic and credit data for B2B entities.
pub struct DunBradstreetProvider {
    mock_mode: bool,
    api_key:   Option<String>,
    client:    reqwest::Client,
}

impl DunBradstreetProvider {
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

        // DUNS: 9-digit number, first digit never 0
        let duns = format!(
            "{}{:08}",
            (h % 9) + 1,
            (h >> 4) % 100_000_000u64
        );

        let credit_idx       = (h % CREDIT_RATINGS.len() as u64) as usize;
        let credit_rating    = CREDIT_RATINGS[credit_idx];

        // Annual revenue: $5M – $5 000M, aligned to name hash
        let revenue_m: u64   = 5 + (h % 4995);
        let annual_revenue   = revenue_m as f64 * 1_000_000.0;

        // Employees: 10 – 50 000
        let employee_count: u64 = 10 + (h % 49990);

        // SIC code
        let sic_idx         = (h % SIC_CODES.len() as u64) as usize;
        let industry_code   = SIC_CODES[sic_idx];

        // Year founded: 1900 – 2020
        let year_founded: u64 = 1900 + (h % 120);

        // Payment index: 0 – 100 (D&B PAYDEX-style)
        let payment_index: u64 = 40 + (h % 61);

        let mut fields: HashMap<String, Value> = HashMap::new();
        fields.insert("dnb_duns_number".to_string(),  json!(duns));
        fields.insert("dnb_credit_rating".to_string(), json!(credit_rating));
        fields.insert("dnb_annual_revenue".to_string(), json!(annual_revenue));
        fields.insert("dnb_employee_count".to_string(), json!(employee_count));
        fields.insert("dnb_industry_code".to_string(), json!(industry_code));
        fields.insert("dnb_year_founded".to_string(), json!(year_founded));
        fields.insert("dnb_payment_index".to_string(), json!(payment_index));
        fields.insert("dnb_enriched_by".to_string(), json!("mock"));

        // Confidence based on how complete the input name is
        let confidence = if name.len() > 10 { 0.92 } else { 0.75 };

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
            anyhow::anyhow!("DNB_API_KEY is required when mock_mode = false")
        })?;

        let name    = attr_str(&req.attributes, "name").unwrap_or("");
        let country = attr_str(&req.attributes, "country").unwrap_or("US");

        // Step 1 – match / identity resolution
        let match_resp = self
            .client
            .get("https://plus.dnb.com/v1/match/cleanseMatch")
            .header("Authorization", format!("Bearer {}", api_key))
            .query(&[
                ("name",            name),
                ("countryISOAlpha2", country),
                ("confidenceLowerLevelThresholdValue", "6"),
            ])
            .send()
            .await?
            .error_for_status()?
            .json::<serde_json::Value>()
            .await?;

        let duns = match_resp
            .pointer("/matchCandidates/0/organization/duns")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .to_string();

        // Step 2 – firmographics
        let firm_resp = self
            .client
            .get(format!("https://plus.dnb.com/v1/data/duns/{}", duns))
            .header("Authorization", format!("Bearer {}", api_key))
            .query(&[("productId", "cmpelk"), ("versionId", "v1")])
            .send()
            .await?
            .error_for_status()?
            .json::<serde_json::Value>()
            .await?;

        let org = &firm_resp["organization"];

        let mut fields: HashMap<String, Value> = HashMap::new();
        fields.insert("dnb_duns_number".to_string(),
            json!(duns));
        fields.insert("dnb_credit_rating".to_string(),
            json!(org.pointer("/creditRatingGroup/0/creditRating/rating").cloned().unwrap_or(Value::Null)));
        fields.insert("dnb_annual_revenue".to_string(),
            json!(org.pointer("/financials/0/yearlyRevenue/0/value").cloned().unwrap_or(Value::Null)));
        fields.insert("dnb_employee_count".to_string(),
            json!(org.pointer("/numberOfEmployees/0/value").cloned().unwrap_or(Value::Null)));
        fields.insert("dnb_industry_code".to_string(),
            json!(org.pointer("/primaryIndustryCodes/0/usSicV4").cloned().unwrap_or(Value::Null)));
        fields.insert("dnb_year_founded".to_string(),
            json!(org["startDate"].clone()));
        fields.insert("dnb_enriched_by".to_string(), json!("dnb_api"));

        Ok(EnrichmentData {
            provider:    self.name().to_string(),
            fields,
            confidence:  0.97,
            enriched_at: Utc::now(),
        })
    }
}

#[async_trait]
impl EnrichmentProvider for DunBradstreetProvider {
    fn name(&self) -> &str {
        "DunBradstreet"
    }

    fn applies_to(&self, req: &EnrichmentRequest) -> bool {
        matches!(
            req.entity_type.as_str(),
            "Customer" | "Vendor" | "Organization" | "Account"
        )
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

    fn make_request(name: &str, entity_type: &str) -> EnrichmentRequest {
        EnrichmentRequest {
            entity_id:   Uuid::new_v4(),
            tenant_id:   Uuid::new_v4(),
            entity_type: entity_type.to_string(),
            attributes:  serde_json::json!({ "name": name }),
        }
    }

    #[test]
    fn test_mock_is_deterministic() {
        let provider = DunBradstreetProvider::new(true, None);
        let req      = make_request("Acme Corporation", "Customer");

        let r1 = provider.mock_enrich(&req);
        let r2 = provider.mock_enrich(&req);

        assert_eq!(r1.fields["dnb_duns_number"],  r2.fields["dnb_duns_number"]);
        assert_eq!(r1.fields["dnb_credit_rating"], r2.fields["dnb_credit_rating"]);
        assert_eq!(r1.fields["dnb_annual_revenue"], r2.fields["dnb_annual_revenue"]);
        assert_eq!(r1.fields["dnb_employee_count"], r2.fields["dnb_employee_count"]);
        assert_eq!(r1.fields["dnb_industry_code"], r2.fields["dnb_industry_code"]);
        assert_eq!(r1.fields["dnb_year_founded"],  r2.fields["dnb_year_founded"]);
    }

    #[test]
    fn test_duns_format() {
        let provider = DunBradstreetProvider::new(true, None);
        let req      = make_request("Globex Industries", "Vendor");
        let result   = provider.mock_enrich(&req);

        let duns = result.fields["dnb_duns_number"]
            .as_str()
            .expect("duns should be a string");

        assert_eq!(duns.len(), 9, "DUNS must be exactly 9 digits");
        assert!(duns.chars().all(|c| c.is_ascii_digit()));
        assert_ne!(duns.chars().next().unwrap(), '0', "first DUNS digit must not be 0");
    }

    #[test]
    fn test_credit_rating_valid() {
        let provider = DunBradstreetProvider::new(true, None);
        let req      = make_request("Initech LLC", "Customer");
        let result   = provider.mock_enrich(&req);

        let rating = result.fields["dnb_credit_rating"]
            .as_str()
            .expect("credit_rating should be a string");

        assert!(
            CREDIT_RATINGS.contains(&rating),
            "credit_rating '{}' not in allowed set",
            rating
        );
    }

    #[test]
    fn test_different_names_yield_different_results() {
        let provider = DunBradstreetProvider::new(true, None);
        let r1 = provider.mock_enrich(&make_request("Alpha Corp",  "Customer"));
        let r2 = provider.mock_enrich(&make_request("Beta Limited", "Customer"));

        // At least one field must differ
        assert!(
            r1.fields["dnb_duns_number"] != r2.fields["dnb_duns_number"]
            || r1.fields["dnb_annual_revenue"] != r2.fields["dnb_annual_revenue"],
            "different names should produce different enrichment"
        );
    }

    #[test]
    fn test_applies_to_correct_types() {
        let provider = DunBradstreetProvider::new(true, None);

        for t in &["Customer", "Vendor", "Organization", "Account"] {
            let req = make_request("X", t);
            assert!(provider.applies_to(&req), "{} should apply", t);
        }

        let location_req = make_request("X", "Location");
        assert!(!provider.applies_to(&location_req));
    }

    #[test]
    fn test_year_founded_range() {
        let provider = DunBradstreetProvider::new(true, None);
        let result   = provider.mock_enrich(&make_request("OldCo", "Vendor"));
        let year     = result.fields["dnb_year_founded"]
            .as_u64()
            .expect("year_founded should be a number");
        assert!((1900..=2020).contains(&year));
    }

    #[test]
    fn test_revenue_positive() {
        let provider = DunBradstreetProvider::new(true, None);
        let result   = provider.mock_enrich(&make_request("RichCorp", "Customer"));
        let rev      = result.fields["dnb_annual_revenue"]
            .as_f64()
            .expect("annual_revenue should be a number");
        assert!(rev >= 5_000_000.0);
    }
}
