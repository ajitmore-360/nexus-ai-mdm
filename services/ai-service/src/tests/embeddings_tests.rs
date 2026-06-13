#[cfg(test)]
mod tests {
    use crate::embeddings::entity_to_text;
    use serde_json::json;

    #[test]
    fn entity_to_text_extracts_string_fields() {
        let attrs = json!({"name": "Acme Corp", "email": "info@acme.com", "country": "US"});
        let text  = entity_to_text(&attrs);
        assert!(text.contains("Acme Corp"));
        assert!(text.contains("info@acme.com"));
        assert!(text.contains("US"));
    }

    #[test]
    fn entity_to_text_skips_nested_objects() {
        let attrs = json!({"name": "Acme", "metadata": {"key": "val"}});
        let text  = entity_to_text(&attrs);
        assert!(!text.contains("metadata"));
        assert!(!text.contains("key"));
    }

    #[test]
    fn entity_to_text_skips_empty_strings() {
        let attrs = json!({"name": "Acme", "phone": "", "email": null});
        let text  = entity_to_text(&attrs);
        let parts: Vec<&str> = text.split(". ").collect();
        // Only "name" should appear — phone and email are empty/null
        assert_eq!(parts.len(), 1);
        assert!(parts[0].contains("Acme"));
    }

    #[test]
    fn entity_to_text_handles_numbers_and_booleans() {
        let attrs = json!({"employees": 450, "is_active": true});
        let text  = entity_to_text(&attrs);
        assert!(text.contains("450"));
        assert!(text.contains("true"));
    }

    #[test]
    fn entity_to_text_empty_object() {
        let text = entity_to_text(&json!({}));
        assert!(text.is_empty());
    }
}
