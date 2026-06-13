use std::collections::HashMap;
use serde_json::Value;
use crate::models::SchemaMapping;

/// Maps raw source fields to canonical field names using a rule table.
pub struct SchemaMapper {
    mappings: Vec<SchemaMapping>,
}

impl SchemaMapper {
    pub fn new(mappings: Vec<SchemaMapping>) -> Self {
        Self { mappings }
    }

    /// Default mappings covering the most common source field aliases.
    pub fn with_defaults() -> Self {
        use crate::models::FieldTransform;
        let mappings = vec![
            sm("company",         "legal_name", None),
            sm("org_name",        "legal_name", None),
            sm("organisation",    "legal_name", None),
            sm("organization",    "legal_name", None),
            sm("email_address",   "email",      Some(FieldTransform::EmailNormalize)),
            sm("email_addr",      "email",      Some(FieldTransform::EmailNormalize)),
            sm("phone_number",    "phone",      Some(FieldTransform::PhoneE164)),
            sm("tel",             "phone",      Some(FieldTransform::PhoneE164)),
            sm("mobile",          "phone",      Some(FieldTransform::PhoneE164)),
            sm("tax_number",      "tax_id",     None),
            sm("vat_id",          "tax_id",     None),
            sm("ein",             "tax_id",     None),
            sm("cust_id",         "customer_id", None),
            sm("customer_number", "customer_id", None),
        ];
        Self { mappings }
    }

    /// Apply mappings: rename source field names to canonical names, applying transforms.
    pub fn map(&self, mut raw_fields: HashMap<String, Value>) -> HashMap<String, Value> {
        let mut out: HashMap<String, Value> = HashMap::new();

        for mapping in &self.mappings {
            if let Some(val) = raw_fields.remove(&mapping.source_field) {
                let canonical_val = match &mapping.transform {
                    None => val,
                    Some(t) => apply_transform(val, t),
                };
                out.insert(mapping.canonical_field.clone(), canonical_val);
            }
        }

        // Pass through unmapped fields unchanged
        out.extend(raw_fields);
        out
    }
}

fn sm(src: &str, canon: &str, t: Option<crate::models::FieldTransform>) -> SchemaMapping {
    SchemaMapping {
        source_field:    src.to_string(),
        canonical_field: canon.to_string(),
        transform:       t,
    }
}

fn apply_transform(val: Value, t: &crate::models::FieldTransform) -> Value {
    use crate::models::FieldTransform;
    let s = match &val {
        Value::String(s) => s.clone(),
        _ => return val,
    };
    let transformed = match t {
        FieldTransform::Lowercase       => s.to_lowercase(),
        FieldTransform::Uppercase       => s.to_uppercase(),
        FieldTransform::TitleCase       => title_case(&s),
        FieldTransform::StripWhitespace => s.split_whitespace().collect::<Vec<_>>().join(" "),
        FieldTransform::EmailNormalize  => s.trim().to_lowercase(),
        FieldTransform::PhoneE164       => normalize_phone(&s),
        FieldTransform::DateIso8601     => parse_date(&s).unwrap_or(s),
    };
    Value::String(transformed)
}

fn title_case(s: &str) -> String {
    s.split_whitespace()
        .map(|word| {
            let mut c = word.chars();
            match c.next() {
                None    => String::new(),
                Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn normalize_phone(s: &str) -> String {
    let digits: String = s.chars().filter(|c| c.is_ascii_digit()).collect();
    match digits.len() {
        10 => format!("+1{}", digits),
        11 if digits.starts_with('1') => format!("+{}", digits),
        _ => s.to_string(),
    }
}

fn parse_date(s: &str) -> Option<String> {
    // Try MM/DD/YYYY
    if let Some(d) = try_parse_mdy(s) { return Some(d); }
    // Try DD-MM-YYYY
    if let Some(d) = try_parse_dmy(s) { return Some(d); }
    None
}

fn try_parse_mdy(s: &str) -> Option<String> {
    let parts: Vec<&str> = s.split('/').collect();
    if parts.len() == 3 {
        let (m, d, y) = (parts[0].trim(), parts[1].trim(), parts[2].trim());
        return Some(format!("{}-{:0>2}-{:0>2}", y, m, d));
    }
    None
}

fn try_parse_dmy(s: &str) -> Option<String> {
    let parts: Vec<&str> = s.split('-').collect();
    if parts.len() == 3 && parts[2].len() == 4 {
        let (d, m, y) = (parts[0].trim(), parts[1].trim(), parts[2].trim());
        return Some(format!("{}-{:0>2}-{:0>2}", y, m, d));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn maps_email_address_to_email() {
        let mapper = SchemaMapper::with_defaults();
        let raw = [("email_address".to_string(), json!("USER@EXAMPLE.COM"))].into();
        let out = mapper.map(raw);
        assert_eq!(out.get("email").unwrap(), &json!("user@example.com"));
        assert!(!out.contains_key("email_address"));
    }

    #[test]
    fn passes_through_unmapped_fields() {
        let mapper = SchemaMapper::with_defaults();
        let raw = [("unknown_field".to_string(), json!("value"))].into();
        let out = mapper.map(raw);
        assert_eq!(out.get("unknown_field").unwrap(), &json!("value"));
    }

    #[test]
    fn phone_normalised_to_e164() {
        let mapper = SchemaMapper::with_defaults();
        let raw = [("phone_number".to_string(), json!("4085550100"))].into();
        let out = mapper.map(raw);
        assert_eq!(out.get("phone").unwrap(), &json!("+14085550100"));
    }

    #[test]
    fn title_case_works() {
        assert_eq!(title_case("hello world"), "Hello World");
        assert_eq!(title_case("ACME CORP"), "ACME CORP"); // only first letter upcased, rest unchanged
    }
}
