#[cfg(test)]
mod tests {
    use crate::matching::semantic_matcher::parse_decision_json_pub;

    #[test]
    fn parse_clean_match_json() {
        // Exposed via a pub wrapper for testing — see below.
        let raw = r#"{"decision":"match","confidence":0.92,"reasoning":"Same tax ID."}"#;
        let result = parse_decision_json_pub(raw).unwrap();
        assert_eq!(result.decision, crate::matching::MatchDecision::Match);
        assert!((result.confidence - 0.92).abs() < 0.001);
        assert_eq!(result.reasoning, "Same tax ID.");
    }

    #[test]
    fn parse_no_match_json() {
        let raw = r#"{"decision":"no_match","confidence":0.78,"reasoning":"Different addresses."}"#;
        let result = parse_decision_json_pub(raw).unwrap();
        assert_eq!(result.decision, crate::matching::MatchDecision::NoMatch);
    }

    #[test]
    fn parse_json_with_leading_text() {
        let raw = r#"Based on my analysis: {"decision":"match","confidence":0.88,"reasoning":"Same entity."}"#;
        let result = parse_decision_json_pub(raw).unwrap();
        assert_eq!(result.decision, crate::matching::MatchDecision::Match);
    }

    #[test]
    fn parse_invalid_decision_returns_none() {
        let raw = r#"{"decision":"maybe","confidence":0.5,"reasoning":"Unsure."}"#;
        assert!(parse_decision_json_pub(raw).is_none());
    }

    #[test]
    fn parse_non_json_returns_none() {
        assert!(parse_decision_json_pub("not json at all").is_none());
    }

    #[test]
    fn confidence_clamped_above_1() {
        let raw = r#"{"decision":"match","confidence":1.5,"reasoning":"high."}"#;
        let result = parse_decision_json_pub(raw).unwrap();
        assert!(result.confidence <= 1.0);
    }
}
