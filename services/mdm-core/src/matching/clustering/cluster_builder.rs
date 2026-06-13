use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use uuid::Uuid;

use contracts::mdm::matching::MatchCluster;

use crate::matching::models::MatchResult;
use crate::matching::policy::MatchingPolicy;

pub struct ClusterBuilder;

impl ClusterBuilder {
    pub fn build(
        matches: &[MatchResult],
        policy: &Arc<MatchingPolicy>,
    ) -> Vec<MatchCluster> {
        let graph = Self::build_graph(matches);

        let mut visited  = HashSet::<Uuid>::new();
        let mut clusters = Vec::<MatchCluster>::new();

        for node in graph.keys() {
            if visited.contains(node) {
                continue;
            }

            let component = Self::connected_component(*node, &graph, &mut visited);

            let confidence      = Self::cluster_confidence(&component, matches);
            let suggested_master = Self::select_master(&component, matches, &graph, policy);

            clusters.push(MatchCluster {
                cluster_id: Uuid::new_v4(),
                entity_ids: component,
                confidence,
                suggested_master,
                metadata: Default::default(),
            });
        }

        clusters
    }

    fn build_graph(matches: &[MatchResult]) -> HashMap<Uuid, HashSet<Uuid>> {
        let mut graph = HashMap::<Uuid, HashSet<Uuid>>::new();

        for m in matches {
            graph.entry(m.source_entity_id).or_default().insert(m.candidate_entity_id);
            graph.entry(m.candidate_entity_id).or_default().insert(m.source_entity_id);
        }

        graph
    }

    fn connected_component(
        start: Uuid,
        graph: &HashMap<Uuid, HashSet<Uuid>>,
        visited: &mut HashSet<Uuid>,
    ) -> Vec<Uuid> {
        let mut stack   = vec![start];
        let mut members = Vec::<Uuid>::new();

        while let Some(node) = stack.pop() {
            if !visited.insert(node) {
                continue;
            }
            members.push(node);
            if let Some(neighbors) = graph.get(&node) {
                for neighbor in neighbors {
                    stack.push(*neighbor);
                }
            }
        }

        members
    }

    fn cluster_confidence(members: &[Uuid], matches: &[MatchResult]) -> f32 {
        let member_set: HashSet<Uuid> = members.iter().copied().collect();

        let scores: Vec<f64> = matches
            .iter()
            .filter(|m| {
                member_set.contains(&m.source_entity_id)
                    && member_set.contains(&m.candidate_entity_id)
            })
            .map(|m| m.score)
            .collect();

        if scores.is_empty() {
            return 0.0;
        }

        (scores.iter().sum::<f64>() / scores.len() as f64) as f32
    }

    /// Single-pass O(m) statistics accumulation per member, then pick master.
    /// Previously this called three separate filter-iterate passes — O(3×m×n).
    fn select_master(
        members: &[Uuid],
        matches: &[MatchResult],
        graph: &HashMap<Uuid, HashSet<Uuid>>,
        policy: &MatchingPolicy,
    ) -> Option<Uuid> {
        if members.is_empty() {
            return None;
        }

        // Accumulate (sum_score, sum_confidence, count) per entity in one pass.
        let mut stats: HashMap<Uuid, (f64, f64, usize)> = members
            .iter()
            .map(|&id| (id, (0.0, 0.0, 0usize)))
            .collect();

        for m in matches {
            for &eid in &[m.source_entity_id, m.candidate_entity_id] {
                if let Some(entry) = stats.get_mut(&eid) {
                    entry.0 += m.score;
                    entry.1 += m.confidence;
                    entry.2 += 1;
                }
            }
        }

        let mut best_entity = None;
        let mut best_score  = f64::MIN;

        for &entity_id in members {
            let degree = graph.get(&entity_id).map_or(0, |n| n.len()) as f64;

            let (sum_score, sum_conf, count) = stats[&entity_id];
            let avg_score = if count > 0 { sum_score / count as f64 } else { 0.0 };
            let avg_conf  = if count > 0 { sum_conf  / count as f64 } else { 0.0 };

            let master_score =
                avg_score * policy.master_weight_score as f64
                + avg_conf  * policy.master_weight_confidence as f64
                + degree    * policy.master_weight_centrality as f64;

            if master_score > best_score {
                best_score  = master_score;
                best_entity = Some(entity_id);
            }
        }

        best_entity
    }
}
