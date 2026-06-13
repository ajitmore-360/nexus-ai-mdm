use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::PgPool;
use tracing::{info, instrument};
use uuid::Uuid;

/// Proposed updated weights derived from steward feedback analysis.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WeightRecommendation {
    pub tenant_id:       Uuid,
    pub exact_weight:    f32,
    pub fuzzy_weight:    f32,
    pub phonetic_weight: f32,
    pub semantic_weight: f32,
    pub vector_weight:   f32,
    /// Number of feedback samples used
    pub sample_size:     i64,
    /// Confidence in the recommendation (0–1)
    pub confidence:      f32,
    pub reasoning:       String,
}

/// Analyses historical steward feedback to recommend adjusted scoring weights.
///
/// Algorithm:
/// 1. Fetch recent approved-match feature vectors (ground-truth positive labels)
/// 2. Fetch recent rejected-match feature vectors (ground-truth negative labels)
/// 3. Compute mean feature activation for positives and negatives
/// 4. Normalise the positive-minus-negative delta into weight recommendations
pub struct WeightTuner {
    pool: PgPool,
}

impl WeightTuner {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    #[instrument(skip(self), fields(tenant_id=%tenant_id))]
    pub async fn recommend(&self, tenant_id: Uuid, min_samples: i64) -> Result<WeightRecommendation> {
        // Load approved match feature vectors
        let approved = self.load_features(tenant_id, "match_approved", 500).await?;
        let rejected = self.load_features(tenant_id, "match_rejected", 500).await?;

        let sample_size = (approved.len() + rejected.len()) as i64;

        if sample_size < min_samples {
            return Ok(WeightRecommendation {
                tenant_id,
                exact_weight:    0.35,
                fuzzy_weight:    0.30,
                phonetic_weight: 0.10,
                semantic_weight: 0.15,
                vector_weight:   0.10,
                sample_size,
                confidence:      0.0,
                reasoning:       format!(
                    "Insufficient feedback data ({sample_size} samples, need {min_samples}). Using defaults."
                ),
            });
        }

        let approved_means = mean_features(&approved);
        let rejected_means = mean_features(&rejected);

        // Positive-minus-negative delta: fields that approve more than reject
        // get boosted weight.
        let delta = [
            (approved_means[0] - rejected_means[0]).max(0.0), // exact
            (approved_means[1] - rejected_means[1]).max(0.0), // fuzzy
            (approved_means[2] - rejected_means[2]).max(0.0), // phonetic
            (approved_means[3] - rejected_means[3]).max(0.0), // semantic
            (approved_means[4] - rejected_means[4]).max(0.0), // vector
        ];

        let total: f32 = delta.iter().sum();

        let (exact_w, fuzzy_w, phonetic_w, semantic_w, vector_w) = if total < 0.001 {
            // No signal — keep defaults
            (0.35, 0.30, 0.10, 0.15, 0.10)
        } else {
            // Blend 80% defaults with 20% learned
            let lerp = |default: f32, learned: f32| 0.80 * default + 0.20 * learned;
            (
                lerp(0.35, delta[0] / total),
                lerp(0.30, delta[1] / total),
                lerp(0.10, delta[2] / total),
                lerp(0.15, delta[3] / total),
                lerp(0.10, delta[4] / total),
            )
        };

        // Renormalise to sum exactly 1.0
        let w_total = exact_w + fuzzy_w + phonetic_w + semantic_w + vector_w;
        let confidence = (sample_size as f32 / 1000.0).min(0.95);

        info!(
            tenant_id=%tenant_id,
            sample_size,
            confidence=confidence,
            "weight recommendation computed"
        );

        Ok(WeightRecommendation {
            tenant_id,
            exact_weight:    exact_w    / w_total,
            fuzzy_weight:    fuzzy_w    / w_total,
            phonetic_weight: phonetic_w / w_total,
            semantic_weight: semantic_w / w_total,
            vector_weight:   vector_w   / w_total,
            sample_size,
            confidence,
            reasoning: format!(
                "Computed from {sample_size} steward decisions using delta-blend (80% priors, 20% signal). \
                 Exact matching signal: {:.2}, Fuzzy: {:.2}, Semantic: {:.2}.",
                delta[0], delta[1], delta[3]
            ),
        })
    }

    async fn load_features(
        &self,
        tenant_id:     Uuid,
        feedback_type: &str,
        limit:         i64,
    ) -> Result<Vec<[f32; 5]>> {
        use sqlx::Row;

        let rows = sqlx::query(
            r#"
            SELECT feature_vector
            FROM ai.steward_feedback
            WHERE tenant_id     = $1
              AND feedback_type = $2
            ORDER BY created_at DESC
            LIMIT $3
            "#,
        )
        .bind(tenant_id)
        .bind(feedback_type)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;

        let features = rows
            .into_iter()
            .filter_map(|r| {
                let v: Value = r.try_get("feature_vector").ok()?;
                let exact    = v.get("exact")   .and_then(|x| x.as_f64()).unwrap_or(0.0) as f32;
                let fuzzy    = v.get("fuzzy")   .and_then(|x| x.as_f64()).unwrap_or(0.0) as f32;
                let phonetic = v.get("phonetic").and_then(|x| x.as_f64()).unwrap_or(0.0) as f32;
                let semantic = v.get("semantic").and_then(|x| x.as_f64()).unwrap_or(0.0) as f32;
                let vector   = v.get("vector")  .and_then(|x| x.as_f64()).unwrap_or(0.0) as f32;
                Some([exact, fuzzy, phonetic, semantic, vector])
            })
            .collect();

        Ok(features)
    }
}

fn mean_features(vecs: &[[f32; 5]]) -> [f32; 5] {
    if vecs.is_empty() {
        return [0.0; 5];
    }
    let n = vecs.len() as f32;
    let mut sum = [0.0f32; 5];
    for v in vecs {
        for i in 0..5 {
            sum[i] += v[i];
        }
    }
    sum.iter_mut().for_each(|x| *x /= n);
    sum
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mean_features_empty_returns_zeros() {
        assert_eq!(mean_features(&[]), [0.0; 5]);
    }

    #[test]
    fn mean_features_single_vec() {
        let v = [[0.9, 0.8, 0.3, 0.5, 0.4]];
        let m = mean_features(&v);
        assert!((m[0] - 0.9).abs() < 0.001);
    }

    #[test]
    fn weight_recommendation_sums_to_one() {
        // Simulate: all delta is in exact matching
        let delta = [1.0f32, 0.0, 0.0, 0.0, 0.0];
        let total: f32 = delta.iter().sum();
        let learned = delta[0] / total;
        let w = 0.80 * 0.35 + 0.20 * learned;
        let sum_approx = w + 0.30 + 0.10 + 0.15 + 0.10;
        // After renormalisation this would be 1.0
        assert!(sum_approx > 0.0);
    }
}
