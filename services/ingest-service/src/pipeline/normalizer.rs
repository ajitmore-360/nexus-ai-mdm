//! Field-level normalization applied after schema mapping.
//!
//! Each `SchemaMapping` may carry a `FieldTransform` variant that is
//! executed here against the mapped canonical value.

use crate::models::{FieldTransform, IngestRecord, SchemaMapping};

// ============================================================
// NORMALIZER
// ============================================================

pub struct Normalizer;

impl Normalizer {
    pub fn new() -> Self {
        Self
    }

    /// Apply all schema mapping transforms to the record's `raw_fields`.
    ///
    /// Fields that have no corresponding mapping entry are left unchanged.
    pub fn normalize_record(
        &self,
        mut record: IngestRecord,
        mappings: &[SchemaMapping],
    ) -> IngestRecord {
        for mapping in mappings {
            if let Some(transform) = &mapping.transform {
                // Work on the canonical field name (already mapped).
                if let Some(value) = record.raw_fields.remove(&mapping.canonical_field) {
                    let transformed = self.apply_transform(value, transform);
                    record
                        .raw_fields
                        .insert(mapping.canonical_field.clone(), transformed);
                }
            }
        }
        record
    }

    // ----------------------------------------------------------
    // Transform dispatch
    // ----------------------------------------------------------

    fn apply_transform(
        &self,
        value: serde_json::Value,
        transform: &FieldTransform,
    ) -> serde_json::Value {
        match value {
            serde_json::Value::String(s) => {
                let result = match transform {
                    FieldTransform::Lowercase => s.to_lowercase(),
                    FieldTransform::Uppercase => s.to_uppercase(),
                    FieldTransform::TitleCase => to_title_case(&s),
                    FieldTransform::StripWhitespace => s.trim().to_string(),
                    FieldTransform::PhoneE164 => normalize_phone_e164(&s),
                    FieldTransform::EmailNormalize => normalize_email(&s),
                    FieldTransform::DateIso8601 => {
                        normalize_date_iso8601(&s).unwrap_or(s)
                    }
                };
                serde_json::Value::String(result)
            }
            // Non-string values pass through without modification.
            other => other,
        }
    }
}

impl Default for Normalizer {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================
// PURE TRANSFORM FUNCTIONS
// ============================================================

/// Capitalise the first letter of every whitespace-separated word.
pub fn to_title_case(s: &str) -> String {
    s.split_whitespace()
        .map(|word| {
            let mut chars = word.chars();
            match chars.next() {
                None => String::new(),
                Some(first) => {
                    first.to_uppercase().collect::<String>() + chars.as_str()
                }
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// Normalise a phone number to E.164 format.
///
/// - Strips all non-digit characters.
/// - If exactly 10 digits remain, prepends `+1` (US/Canada assumption).
/// - If 11 digits starting with `1`, prepends `+`.
/// - Otherwise returns the digits prefixed with `+`.
pub fn normalize_phone_e164(s: &str) -> String {
    let digits: String = s.chars().filter(|c| c.is_ascii_digit()).collect();
    match digits.len() {
        10 => format!("+1{}", digits),
        11 if digits.starts_with('1') => format!("+{}", digits),
        _ if !digits.is_empty() => format!("+{}", digits),
        _ => s.to_string(),
    }
}

/// Normalise an email address: lowercase the whole string and strip whitespace.
pub fn normalize_email(s: &str) -> String {
    s.trim().to_lowercase()
}

/// Attempt to parse several common date formats and return ISO 8601 (YYYY-MM-DD).
///
/// Supported input formats:
/// - `MM/DD/YYYY`
/// - `DD-MM-YYYY`
/// - `YYYY/MM/DD`
/// - `YYYY-MM-DD` (already canonical, returned as-is after validation)
pub fn normalize_date_iso8601(s: &str) -> Option<String> {
    let s = s.trim();

    // Try each format in order.
    if let Some(date) = try_parse_slash_mdy(s) {
        return Some(date);
    }
    if let Some(date) = try_parse_dash_dmy(s) {
        return Some(date);
    }
    if let Some(date) = try_parse_slash_ymd(s) {
        return Some(date);
    }
    if let Some(date) = try_parse_dash_ymd(s) {
        return Some(date);
    }

    None
}

fn try_parse_slash_mdy(s: &str) -> Option<String> {
    // MM/DD/YYYY
    let parts: Vec<&str> = s.split('/').collect();
    if parts.len() != 3 {
        return None;
    }
    let month: u32 = parts[0].parse().ok()?;
    let day: u32 = parts[1].parse().ok()?;
    let year: i32 = parts[2].parse().ok()?;
    validate_date(year, month, day)
}

fn try_parse_dash_dmy(s: &str) -> Option<String> {
    // DD-MM-YYYY
    let parts: Vec<&str> = s.split('-').collect();
    if parts.len() != 3 || parts[2].len() != 4 {
        return None;
    }
    let day: u32 = parts[0].parse().ok()?;
    let month: u32 = parts[1].parse().ok()?;
    let year: i32 = parts[2].parse().ok()?;
    validate_date(year, month, day)
}

fn try_parse_slash_ymd(s: &str) -> Option<String> {
    // YYYY/MM/DD
    let parts: Vec<&str> = s.split('/').collect();
    if parts.len() != 3 || parts[0].len() != 4 {
        return None;
    }
    let year: i32 = parts[0].parse().ok()?;
    let month: u32 = parts[1].parse().ok()?;
    let day: u32 = parts[2].parse().ok()?;
    validate_date(year, month, day)
}

fn try_parse_dash_ymd(s: &str) -> Option<String> {
    // YYYY-MM-DD
    let parts: Vec<&str> = s.split('-').collect();
    if parts.len() != 3 || parts[0].len() != 4 {
        return None;
    }
    let year: i32 = parts[0].parse().ok()?;
    let month: u32 = parts[1].parse().ok()?;
    let day: u32 = parts[2].parse().ok()?;
    validate_date(year, month, day)
}

fn validate_date(year: i32, month: u32, day: u32) -> Option<String> {
    if month == 0 || month > 12 || day == 0 || day > 31 || year < 1 {
        return None;
    }
    Some(format!("{:04}-{:02}-{:02}", year, month, day))
}

// ============================================================
// TESTS
// ============================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::SchemaMapping;
    use std::collections::HashMap;

    fn make_record(fields: Vec<(&str, &str)>) -> IngestRecord {
        IngestRecord {
            source_system: "test".to_string(),
            source_entity_id: "1".to_string(),
            entity_type: "Customer".to_string(),
            raw_fields: fields
                .into_iter()
                .map(|(k, v)| (k.to_string(), serde_json::Value::String(v.to_string())))
                .collect::<HashMap<_, _>>(),
            received_at: chrono::Utc::now(),
        }
    }

    fn mapping(
        source: &str,
        canonical: &str,
        transform: FieldTransform,
    ) -> SchemaMapping {
        SchemaMapping {
            source_field: source.to_string(),
            canonical_field: canonical.to_string(),
            transform: Some(transform),
        }
    }

    // --- Individual transforms ---

    #[test]
    fn lowercase_transform() {
        let n = Normalizer::new();
        let record = make_record(vec![("email", "User@Example.COM")]);
        let mappings = vec![mapping("email", "email", FieldTransform::Lowercase)];
        let out = n.normalize_record(record, &mappings);
        assert_eq!(
            out.raw_fields["email"],
            serde_json::Value::String("user@example.com".to_string())
        );
    }

    #[test]
    fn uppercase_transform() {
        let n = Normalizer::new();
        let record = make_record(vec![("code", "abc123")]);
        let mappings = vec![mapping("code", "code", FieldTransform::Uppercase)];
        let out = n.normalize_record(record, &mappings);
        assert_eq!(
            out.raw_fields["code"],
            serde_json::Value::String("ABC123".to_string())
        );
    }

    #[test]
    fn title_case_transform() {
        let n = Normalizer::new();
        let record = make_record(vec![("name", "john michael doe")]);
        let mappings = vec![mapping("name", "name", FieldTransform::TitleCase)];
        let out = n.normalize_record(record, &mappings);
        assert_eq!(
            out.raw_fields["name"],
            serde_json::Value::String("John Michael Doe".to_string())
        );
    }

    #[test]
    fn strip_whitespace_transform() {
        let n = Normalizer::new();
        let record = make_record(vec![("name", "  Acme Corp  ")]);
        let mappings =
            vec![mapping("name", "name", FieldTransform::StripWhitespace)];
        let out = n.normalize_record(record, &mappings);
        assert_eq!(
            out.raw_fields["name"],
            serde_json::Value::String("Acme Corp".to_string())
        );
    }

    // --- Phone ---

    #[test]
    fn phone_10_digit() {
        assert_eq!(normalize_phone_e164("(415) 555-1234"), "+14155551234");
    }

    #[test]
    fn phone_11_digit_with_country() {
        assert_eq!(normalize_phone_e164("+1 415 555 1234"), "+14155551234");
    }

    #[test]
    fn phone_already_e164() {
        assert_eq!(normalize_phone_e164("+44 20 7946 0958"), "+442079460958");
    }

    // --- Email ---

    #[test]
    fn email_normalize() {
        assert_eq!(normalize_email("  USER@EXAMPLE.COM  "), "user@example.com");
    }

    // --- Date ---

    #[test]
    fn date_mdy_slash() {
        assert_eq!(
            normalize_date_iso8601("12/31/2023"),
            Some("2023-12-31".to_string())
        );
    }

    #[test]
    fn date_dmy_dash() {
        assert_eq!(
            normalize_date_iso8601("31-12-2023"),
            Some("2023-12-31".to_string())
        );
    }

    #[test]
    fn date_ymd_slash() {
        assert_eq!(
            normalize_date_iso8601("2023/06/15"),
            Some("2023-06-15".to_string())
        );
    }

    #[test]
    fn date_already_iso() {
        assert_eq!(
            normalize_date_iso8601("2023-06-15"),
            Some("2023-06-15".to_string())
        );
    }

    #[test]
    fn date_invalid_returns_none() {
        assert_eq!(normalize_date_iso8601("not-a-date"), None);
    }

    // --- Title case edge cases ---

    #[test]
    fn title_case_empty() {
        assert_eq!(to_title_case(""), "");
    }

    #[test]
    fn title_case_single_word() {
        assert_eq!(to_title_case("hello"), "Hello");
    }
}
