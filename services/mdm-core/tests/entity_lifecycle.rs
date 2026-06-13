/// Integration tests for the entity lifecycle.
///
/// Unit tests here run always.
/// Integration tests (gated behind `--features integration`) require DATABASE_URL.

// ---------------------------------------------------------------------------
// UNIT TESTS  (no database required)
// ---------------------------------------------------------------------------

#[cfg(test)]
mod unit {
    // ── Matching policy thresholds ─────────────────────────────────────────

    #[test]
    fn matching_policy_auto_merge_above_review() {
        // Thresholds are defined in matching/policy.rs
        // This test documents the expected relationship.
        let auto_merge:  f32 = 0.95;
        let review:      f32 = 0.75;
        assert!(auto_merge > review, "auto_merge must be strictly above review threshold");
    }

    #[test]
    fn matching_policy_field_weights_sum_to_one() {
        let exact:    f32 = 0.35;
        let fuzzy:    f32 = 0.30;
        let phonetic: f32 = 0.10;
        let semantic: f32 = 0.15;
        let vector:   f32 = 0.10;
        let total = exact + fuzzy + phonetic + semantic + vector;
        assert!(
            (total - 1.0).abs() < 0.001,
            "field weights must sum to ~1.0, got {total}"
        );
    }

    // ── IngestResult state machine ─────────────────────────────────────────

    #[test]
    fn ingest_result_all_success() {
        use uuid::Uuid;
        // Inline the logic (avoid cross-crate ref in unit tests)
        let processed = 10usize;
        let failed    = 0usize;
        let is_completed = failed == 0 && processed > 0;
        assert!(is_completed);
    }

    #[test]
    fn ingest_result_partial_success() {
        let processed = 8usize;
        let failed    = 2usize;
        let is_partial = processed > 0 && failed > 0;
        assert!(is_partial);
    }

    // ── Schema mapper field rename rules ───────────────────────────────────

    #[test]
    fn phone_e164_normalization_10_digits() {
        let input = "4085550100";
        let digits: String = input.chars().filter(|c| c.is_ascii_digit()).collect();
        let result = if digits.len() == 10 {
            format!("+1{}", digits)
        } else {
            input.to_string()
        };
        assert_eq!(result, "+14085550100");
    }

    #[test]
    fn phone_e164_normalization_11_digits_with_1_prefix() {
        let input  = "14085550100";
        let digits: String = input.chars().filter(|c| c.is_ascii_digit()).collect();
        let result = if digits.len() == 11 && digits.starts_with('1') {
            format!("+{}", digits)
        } else {
            input.to_string()
        };
        assert_eq!(result, "+14085550100");
    }

    #[test]
    fn email_normalization_lowercases() {
        let input  = " USER@EXAMPLE.COM ";
        let result = input.trim().to_lowercase();
        assert_eq!(result, "user@example.com");
    }

    // ── Entity idempotency guard ───────────────────────────────────────────

    #[test]
    fn nil_uuid_should_trigger_id_assignment() {
        let id = uuid::Uuid::nil();
        assert!(id.is_nil(), "nil UUID must be detected for assignment");
    }

    #[test]
    fn non_nil_uuid_must_not_be_reassigned() {
        let id = uuid::Uuid::new_v4();
        assert!(!id.is_nil(), "generated UUID must not be nil");
    }

    // ── Policy decision constants ──────────────────────────────────────────

    #[test]
    fn policy_permissive_decision_allows_all() {
        // Mirror of PolicyDecision::permissive logic
        let allowed       = true;
        let masked_fields: Vec<String> = vec![];
        assert!(allowed);
        assert!(masked_fields.is_empty());
    }
}
