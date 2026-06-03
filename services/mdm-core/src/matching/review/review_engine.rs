use std::sync::Arc;

use anyhow::Result;
use uuid::Uuid;

use crate::matching::models::{
    MatchDecision,
    MatchResult,
    ReviewCase,
    ReviewPriority,
};

pub struct ReviewEngine {
    auto_merge_threshold: f64,
    review_threshold: f64,
}

impl ReviewEngine {
    pub fn new(
        auto_merge_threshold: f64,
        review_threshold: f64,
    ) -> Self {
        Self {
            auto_merge_threshold,
            review_threshold,
        }
    }

    pub fn evaluate(
        &self,
        result: &MatchResult,
    ) -> MatchDecision {

        if result.score >= self.auto_merge_threshold {
            return MatchDecision::AutoMerge;
        }

        if result.score >= self.review_threshold {
            return MatchDecision::HumanReview;
        }

        MatchDecision::NoMatch
    }

    pub fn create_review_case(
        &self,
        result: &MatchResult,
    ) -> Option<ReviewCase> {

        if self.evaluate(result)
            != MatchDecision::HumanReview
        {
            return None;
        }

        Some(ReviewCase {
            review_id: Uuid::new_v4(),
            source_entity_id: result.source_entity_id,
            candidate_entity_id: result.candidate_entity_id,
            score: result.score,
            priority: self.calculate_priority(result.score),
            reason: result.explanations.join("; "),
        })
    }

    fn calculate_priority(
        &self,
        score: f64,
    ) -> ReviewPriority {

        if score >= 0.95 {
            ReviewPriority::Critical
        } else if score >= 0.90 {
            ReviewPriority::High
        } else if score >= 0.85 {
            ReviewPriority::Medium
        } else {
            ReviewPriority::Low
        }
    }
}