pub mod customer;
pub mod vendor;
pub mod product;

use std::collections::HashMap;
use serde_json::Value;

/// Every generator must implement this trait.
pub trait EntityGenerator {
    /// Generate `count` unique base records.
    fn generate(count: usize, seed: u64) -> Vec<HashMap<String, Value>>;
}

/// Inject approximate `pct`% duplicate records into `entities`.
/// Returns the number of duplicates actually added.
///
/// Each duplicate is a near-copy of an existing record with minor
/// surface variations that mimic real-world data-quality issues.
pub fn add_duplicates(
    entities:  &mut Vec<HashMap<String, Value>>,
    pct:       f32,
    seed:      u64,
    mutate_fn: fn(&HashMap<String, Value>, &mut rand::rngs::StdRng) -> HashMap<String, Value>,
) -> usize {
    use rand::SeedableRng;
    use rand::seq::SliceRandom;

    let base_count = entities.len();
    if base_count == 0 || pct <= 0.0 {
        return 0;
    }

    let dup_count = ((base_count as f32 * pct / 100.0).round() as usize).max(1);
    let mut rng   = rand::rngs::StdRng::seed_from_u64(seed.wrapping_add(9999));

    let indices: Vec<usize> = (0..base_count).collect();
    let chosen: Vec<usize>  = indices
        .choose_multiple(&mut rng, dup_count.min(base_count))
        .cloned()
        .collect();

    let mut duplicates = Vec::with_capacity(chosen.len());
    for idx in &chosen {
        let original  = &entities[*idx];
        let duplicate = mutate_fn(original, &mut rng);
        duplicates.push(duplicate);
    }

    let actual = duplicates.len();
    entities.extend(duplicates);
    actual
}
