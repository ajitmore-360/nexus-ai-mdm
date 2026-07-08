use std::sync::Arc;

use chrono::Utc;
use uuid::Uuid;

use crate::matching::{
    models::{
        MatchDecision,
        MatchEvaluationResult,
        ReviewCase,
        ReviewPriority,
        ReviewReason,
    },
    policy::MatchingPolicy,
};

#[allow(dead_code)]
pub struct ReviewEngine {
    policy: Arc<MatchingPolicy>,
}

#[allow(dead_code)]
impl ReviewEngine {
    pub fn new(policy: Arc<MatchingPolicy>) -> Self {
        Self { policy }
    }

    pub fn evaluate(&self, result: &MatchEvaluationResult) -> MatchDecision {
        let score = result.breakdown.total_score;

        if self.requires_review(result) {
            return MatchDecision::HumanReview;
        }

        if score >= self.policy.auto_merge_threshold {
            return MatchDecision::AutoMerge;
        }

        if score >= self.policy.review_threshold {
            return MatchDecision::HumanReview;
        }

        MatchDecision::NoMatch
    }

    pub fn create_review_case(
        &self,
        source_entity_id: Uuid,
        candidate_entity_id: Uuid,
        result: &MatchEvaluationResult,
    ) -> Option<ReviewCase> {

        if self.evaluate(result) != MatchDecision::HumanReview {
            return None;
        }

        let score = result.breakdown.total_score;

        Some(ReviewCase {
            review_id: Uuid::new_v4(),
            source_entity_id,
            candidate_entity_id,
            score: score as f64,
            priority: self.calculate_priority(score),
            reason: self.build_reason(result),
            review_reason: self.determine_reason(result),
            created_at: Utc::now(),
        })
    }

    fn requires_review(&self, result: &MatchEvaluationResult) -> bool {
        let score = result.breakdown.total_score;

        if score >= self.policy.review_threshold && score < self.policy.auto_merge_threshold {
            return true;
        }

        result.field_results.iter().any(|f| f.score < 0.50)
    }

    fn determine_reason(&self, result: &MatchEvaluationResult) -> ReviewReason {
        let score = result.breakdown.total_score;

        if result.field_results.iter().any(|f| f.score < 0.50) {
            return ReviewReason::ConflictingAttributes;
        }

        if score >= self.policy.review_threshold && score < self.policy.auto_merge_threshold {
            return ReviewReason::ScoreInGreyZone;
        }

        ReviewReason::AIRecommendation
    }

    fn calculate_priority(&self, score: f32) -> ReviewPriority {
        if score >= self.policy.auto_merge_threshold {
            ReviewPriority::Critical
        } else if score >= 0.90 {
            ReviewPriority::High
        } else if score >= 0.85 {
            ReviewPriority::Medium
        } else {
            ReviewPriority::Low
        }
    }

    fn build_reason(&self, result: &MatchEvaluationResult) -> String {
        let mut reasons = Vec::<String>::new();
        reasons.push(format!("Match score {:.4}", result.breakdown.total_score));

        for field in &result.field_results {
            if field.score < 0.50 {
                reasons.push(format!(
                    "Conflicting field {} ({:.2})",
                    field.field, field.score
                ));
            }
        }

        reasons.join("; ")
    }

    pub fn detect_ambiguous_candidates(&self, top_score: f32, second_score: f32) -> bool {
        (top_score - second_score).abs() < self.policy.ambiguity_delta
    }
}
