//! Address validation and standardisation provider.
//!
//! Mock mode applies deterministic formatting rules (title-case, state
//! abbreviation, ZIP normalisation) so that tests remain stable.
//! Real integrations would call a USPS / CASS-certified service (e.g. Smarty,
//! Lob, SmartyStreets) — the stub is wired to the Smarty US Street Address API
//! endpoint when mock_mode = false.

use std::collections::HashMap;

use async_trait::async_trait;
use chrono::Utc;
use serde_json::{json, Value};

use super::{attr_str, name_hash, EnrichmentData, EnrichmentProvider, EnrichmentRequest};

// ── deliverability labels ─────────────────────────────────────────────────────
const DELIVERABILITY: &[&str] = &["Deliverable", "Deliverable", "Deliverable", "Vacant", "Undeliverable"];

// ── address type labels ───────────────────────────────────────────────────────
const ADDR_TYPES: &[&str] = &["Commercial", "Commercial", "Residential", "PO Box"];

// ── well-known US state abbreviations for normalisation ───────────────────────
const STATE_ABBREVS: &[(&str, &str)] = &[
    ("california",     "CA"),
    ("new york",       "NY"),
    ("texas",          "TX"),
    ("florida",        "FL"),
    ("illinois",       "IL"),
    ("pennsylvania",   "PA"),
    ("ohio",           "OH"),
    ("georgia",        "GA"),
    ("michigan",       "MI"),
    ("washington",     "WA"),
    ("arizona",        "AZ"),
    ("colorado",       "CO"),
    ("indiana",        "IN"),
    ("nevada",         "NV"),
    ("oregon",         "OR"),
    ("minnesota",      "MN"),
    ("wisconsin",      "WI"),
    ("missouri",       "MO"),
    ("virginia",       "VA"),
    ("north carolina", "NC"),
    ("south carolina", "SC"),
    ("massachusetts",  "MA"),
    ("maryland",       "MD"),
    ("tennessee",      "TN"),
    ("kentucky",       "KY"),
    ("louisiana",      "LA"),
    ("alabama",        "AL"),
    ("iowa",           "IA"),
    ("kansas",         "KS"),
    ("arkansas",       "AR"),
    ("utah",           "UT"),
    ("new mexico",     "NM"),
    ("nebraska",       "NE"),
    ("idaho",          "ID"),
    ("mississippi",    "MS"),
    ("connecticut",    "CT"),
    ("oklahoma",       "OK"),
    ("new jersey",     "NJ"),
];

/// Address validation provider — standardises postal address fields.
pub struct AddressProvider {
    mock_mode: bool,
    api_key:   Option<String>,
    client:    reqwest::Client,
}

impl AddressProvider {
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
        let street  = attr_str(&req.attributes, "address_street")
            .or_else(|| attr_str(&req.attributes, "street"))
            .unwrap_or("");
        let city    = attr_str(&req.attributes, "address_city")
            .or_else(|| attr_str(&req.attributes, "city"))
            .unwrap_or("");
        let state   = attr_str(&req.attributes, "address_state")
            .or_else(|| attr_str(&req.attributes, "state"))
            .unwrap_or("");
        let zip     = attr_str(&req.attributes, "address_zip")
            .or_else(|| attr_str(&req.attributes, "zip"))
            .unwrap_or("");
        let country = attr_str(&req.attributes, "address_country")
            .or_else(|| attr_str(&req.attributes, "country"))
            .unwrap_or("US");

        // Standardise street → title case
        let std_street  = to_title_case(street);

        // Standardise city → title case
        let std_city    = to_title_case(city);

        // Standardise state → abbreviation if recognised
        let std_state   = normalise_state(state);

        // Standardise ZIP → first 5 digits
        let std_zip     = normalise_zip(zip);

        // Standardise country → ISO 3166-1 alpha-2 upper-case
        let std_country = country.to_uppercase();

        // Build validated_address string
        let validated_address = format!(
            "{}, {}, {} {}, {}",
            std_street, std_city, std_state, std_zip, std_country
        );

        // Deterministic deliverability / type from combined address hash
        let combined = format!("{}{}{}{}", street, city, state, zip);
        let h        = name_hash(&combined);
        let deliv    = DELIVERABILITY[(h % DELIVERABILITY.len() as u64) as usize];
        let atype    = ADDR_TYPES[(h % ADDR_TYPES.len() as u64) as usize];

        // DPV footnote codes (USPS style)
        let dpv_footnote = if deliv == "Deliverable" { "AA" } else { "CC" };

        let mut fields: HashMap<String, Value> = HashMap::new();
        fields.insert("addr_validated_street".to_string(),  json!(std_street));
        fields.insert("addr_validated_city".to_string(),    json!(std_city));
        fields.insert("addr_validated_state".to_string(),   json!(std_state));
        fields.insert("addr_validated_zip".to_string(),     json!(std_zip));
        fields.insert("addr_validated_country".to_string(), json!(std_country));
        fields.insert("addr_validated_address".to_string(), json!(validated_address));
        fields.insert("addr_address_type".to_string(),      json!(atype));
        fields.insert("addr_deliverability".to_string(),    json!(deliv));
        fields.insert("addr_dpv_footnote".to_string(),      json!(dpv_footnote));
        fields.insert("addr_enriched_by".to_string(),       json!("mock"));

        // Confidence: lower when any key field is blank
        let completeness = [street, city, state, zip]
            .iter()
            .filter(|s| !s.is_empty())
            .count();
        let confidence = 0.50 + (completeness as f32) * 0.125;

        EnrichmentData {
            provider:    self.name().to_string(),
            fields,
            confidence,
            enriched_at: Utc::now(),
        }
    }

    // ── real API call (Smarty US Street Address) ──────────────────────────────

    async fn real_enrich(&self, req: &EnrichmentRequest) -> anyhow::Result<EnrichmentData> {
        let api_key = self.api_key.as_deref().ok_or_else(|| {
            anyhow::anyhow!("ADDRESS_API_KEY is required when mock_mode = false")
        })?;

        let street = attr_str(&req.attributes, "address_street")
            .or_else(|| attr_str(&req.attributes, "street"))
            .unwrap_or("");
        let city   = attr_str(&req.attributes, "address_city")
            .or_else(|| attr_str(&req.attributes, "city"))
            .unwrap_or("");
        let state  = attr_str(&req.attributes, "address_state")
            .or_else(|| attr_str(&req.attributes, "state"))
            .unwrap_or("");
        let zip    = attr_str(&req.attributes, "address_zip")
            .or_else(|| attr_str(&req.attributes, "zip"))
            .unwrap_or("");

        let resp = self
            .client
            .get("https://us-street.api.smarty.com/street-address")
            .query(&[
                ("auth-id",   api_key),
                ("street",    street),
                ("city",      city),
                ("state",     state),
                ("zipcode",   zip),
                ("candidates", "1"),
                ("match",      "enhanced"),
            ])
            .send()
            .await?
            .error_for_status()?
            .json::<serde_json::Value>()
            .await?;

        let entry = resp
            .get(0)
            .ok_or_else(|| anyhow::anyhow!("Smarty: no candidates returned"))?;

        let comp  = &entry["components"];
        let meta  = &entry["metadata"];
        let analysis = &entry["analysis"];

        let validated_address = entry["delivery_line_1"]
            .as_str()
            .unwrap_or("")
            .to_string();

        let deliverability = match analysis["dpv_match_code"].as_str().unwrap_or("") {
            "Y" | "S" => "Deliverable",
            "D"       => "Deliverable",
            "V"       => "Vacant",
            _         => "Undeliverable",
        };

        let atype = match meta["rdi"].as_str().unwrap_or("") {
            "Residential" => "Residential",
            "Commercial"  => "Commercial",
            _             => "Unknown",
        };

        let mut fields: HashMap<String, Value> = HashMap::new();
        fields.insert("addr_validated_street".to_string(),
            json!(entry["delivery_line_1"].as_str().unwrap_or("")));
        fields.insert("addr_validated_city".to_string(),
            json!(comp["city_name"].as_str().unwrap_or("")));
        fields.insert("addr_validated_state".to_string(),
            json!(comp["state_abbreviation"].as_str().unwrap_or("")));
        fields.insert("addr_validated_zip".to_string(),
            json!(comp["zipcode"].as_str().unwrap_or("")));
        fields.insert("addr_validated_country".to_string(), json!("US"));
        fields.insert("addr_validated_address".to_string(), json!(validated_address));
        fields.insert("addr_address_type".to_string(),      json!(atype));
        fields.insert("addr_deliverability".to_string(),    json!(deliverability));
        fields.insert("addr_dpv_footnote".to_string(),
            json!(analysis["dpv_footnotes"].as_str().unwrap_or("")));
        fields.insert("addr_enriched_by".to_string(), json!("smarty_api"));

        Ok(EnrichmentData {
            provider:    self.name().to_string(),
            fields,
            confidence:  0.98,
            enriched_at: Utc::now(),
        })
    }
}

#[async_trait]
impl EnrichmentProvider for AddressProvider {
    fn name(&self) -> &str {
        "AddressValidation"
    }

    /// Applies to any entity that has at least one recognisable address field.
    fn applies_to(&self, req: &EnrichmentRequest) -> bool {
        let addr_keys = [
            "address_street", "street",
            "address_city",   "city",
            "address_zip",    "zip",
        ];
        addr_keys.iter().any(|k| {
            req.attributes
                .get(k)
                .and_then(|v| v.as_str())
                .map(|s| !s.is_empty())
                .unwrap_or(false)
        })
    }

    async fn enrich(&self, req: &EnrichmentRequest) -> anyhow::Result<EnrichmentData> {
        if self.mock_mode {
            Ok(self.mock_enrich(req))
        } else {
            self.real_enrich(req).await
        }
    }
}

// ── formatting helpers ────────────────────────────────────────────────────────

/// Title-case a string: capitalise the first letter of every word.
pub fn to_title_case(s: &str) -> String {
    s.split_whitespace()
        .map(|word| {
            let mut chars = word.chars();
            match chars.next() {
                None    => String::new(),
                Some(c) => c.to_uppercase().to_string() + chars.as_str(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// Return the 2-letter abbreviation for a known US state name, or return the
/// original value (already abbreviated or non-US).
pub fn normalise_state(state: &str) -> String {
    let lower = state.trim().to_lowercase();
    // Already a 2-letter code?
    if lower.len() == 2 && lower.chars().all(|c| c.is_alphabetic()) {
        return state.trim().to_uppercase();
    }
    for (full, abbr) in STATE_ABBREVS {
        if lower == *full {
            return abbr.to_string();
        }
    }
    // Unknown → title-case as-is
    to_title_case(state.trim())
}

/// Normalise a ZIP/postal code: strip spaces and take the first 5 digits
/// for US ZIPs (pass international codes through).
pub fn normalise_zip(zip: &str) -> String {
    let clean: String = zip.chars().filter(|c| !c.is_whitespace()).collect();
    // US ZIP+4 → just ZIP-5
    if clean.len() > 5 && clean[..5].chars().all(|c| c.is_ascii_digit()) {
        clean[..5].to_string()
    } else {
        clean
    }
}

// ── tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    fn make_req(attrs: serde_json::Value) -> EnrichmentRequest {
        EnrichmentRequest {
            entity_id:   Uuid::new_v4(),
            tenant_id:   Uuid::new_v4(),
            entity_type: "Customer".to_string(),
            attributes:  attrs,
        }
    }

    #[test]
    fn test_mock_is_deterministic() {
        let p = AddressProvider::new(true, None);
        let req = make_req(serde_json::json!({
            "address_street": "123 main st",
            "address_city":   "springfield",
            "address_state":  "illinois",
            "address_zip":    "62701",
        }));

        let r1 = p.mock_enrich(&req);
        let r2 = p.mock_enrich(&req);

        assert_eq!(r1.fields["addr_validated_street"],  r2.fields["addr_validated_street"]);
        assert_eq!(r1.fields["addr_deliverability"],    r2.fields["addr_deliverability"]);
        assert_eq!(r1.fields["addr_address_type"],      r2.fields["addr_address_type"]);
    }

    #[test]
    fn test_street_title_case() {
        let p = AddressProvider::new(true, None);
        let req = make_req(serde_json::json!({
            "address_street": "123 main street",
            "address_city":   "anytown",
            "address_state":  "ca",
            "address_zip":    "90210",
        }));
        let result = p.mock_enrich(&req);
        assert_eq!(
            result.fields["addr_validated_street"].as_str().unwrap(),
            "123 Main Street"
        );
    }

    #[test]
    fn test_state_normalisation() {
        assert_eq!(normalise_state("california"), "CA");
        assert_eq!(normalise_state("California"), "CA");
        assert_eq!(normalise_state("CA"),          "CA");
        assert_eq!(normalise_state("ca"),          "CA");
        assert_eq!(normalise_state("new york"),    "NY");
        assert_eq!(normalise_state("TX"),          "TX");
    }

    #[test]
    fn test_zip_normalisation() {
        assert_eq!(normalise_zip("90210"),         "90210");
        assert_eq!(normalise_zip("90210-3456"),    "90210");
        assert_eq!(normalise_zip("90210 3456"),    "90210");
        assert_eq!(normalise_zip(" 10001 "),       "10001");
        assert_eq!(normalise_zip("EC1A 1BB"),      "EC1A1BB"); // UK postal
    }

    #[test]
    fn test_deliverability_valid() {
        let p   = AddressProvider::new(true, None);
        let req = make_req(serde_json::json!({
            "address_street": "456 Oak Ave",
            "address_city":   "Houston",
            "address_state":  "TX",
            "address_zip":    "77001",
        }));
        let result = p.mock_enrich(&req);
        let deliv  = result.fields["addr_deliverability"].as_str().unwrap();
        assert!(
            DELIVERABILITY.contains(&deliv),
            "deliverability '{}' not in allowed set",
            deliv
        );
    }

    #[test]
    fn test_address_type_valid() {
        let p   = AddressProvider::new(true, None);
        let req = make_req(serde_json::json!({
            "street": "789 Elm Blvd",
            "city":   "Miami",
            "state":  "FL",
            "zip":    "33101",
        }));
        let result = p.mock_enrich(&req);
        let atype  = result.fields["addr_address_type"].as_str().unwrap();
        assert!(
            ADDR_TYPES.contains(&atype),
            "address_type '{}' not in allowed set",
            atype
        );
    }

    #[test]
    fn test_applies_to_with_address_fields() {
        let p = AddressProvider::new(true, None);

        let with_addr = make_req(serde_json::json!({ "address_street": "1 Main St" }));
        assert!(p.applies_to(&with_addr));

        let without_addr = make_req(serde_json::json!({ "name": "NoCorp" }));
        assert!(!p.applies_to(&without_addr));
    }

    #[test]
    fn test_confidence_scales_with_completeness() {
        let p = AddressProvider::new(true, None);

        // All four fields → highest confidence
        let full = p.mock_enrich(&make_req(serde_json::json!({
            "address_street": "1 Main St",
            "address_city":   "Austin",
            "address_state":  "TX",
            "address_zip":    "78701",
        })));

        // Only one field → lower confidence
        let partial = p.mock_enrich(&make_req(serde_json::json!({
            "address_street": "1 Main St",
        })));

        assert!(full.confidence > partial.confidence);
    }

    #[test]
    fn test_to_title_case() {
        assert_eq!(to_title_case("hello world"),   "Hello World");
        assert_eq!(to_title_case("MAIN STREET"),   "MAIN STREET");
        assert_eq!(to_title_case("123 elm blvd"),  "123 Elm Blvd");
        assert_eq!(to_title_case(""),              "");
    }
}
