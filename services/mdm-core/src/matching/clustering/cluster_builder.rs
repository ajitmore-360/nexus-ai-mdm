use std::collections::{
    HashMap,
    HashSet,
};

use uuid::Uuid;

use crate::matching::models::{
    MatchCluster,
    MatchResult,
};

pub struct ClusterBuilder;

impl ClusterBuilder {

    pub fn build(
        matches: &[MatchResult],
    ) -> Vec<MatchCluster> {

        let mut graph:
            HashMap<Uuid, HashSet<Uuid>>
            = HashMap::new();

        for m in matches {

            graph
                .entry(m.source_entity_id)
                .or_default()
                .insert(m.candidate_entity_id);

            graph
                .entry(m.candidate_entity_id)
                .or_default()
                .insert(m.source_entity_id);
        }

        let mut visited =
            HashSet::<Uuid>::new();

        let mut clusters =
            Vec::<MatchCluster>::new();

        for node in graph.keys() {

            if visited.contains(node) {
                continue;
            }

            let mut stack = vec![*node];
            let mut members = Vec::new();

            while let Some(current) =
                stack.pop()
            {
                if !visited.insert(current) {
                    continue;
                }

                members.push(current);

                if let Some(neighbors)
                    = graph.get(&current)
                {
                    for n in neighbors {
                        stack.push(*n);
                    }
                }
            }

            clusters.push(
                MatchCluster {
                    cluster_id:
                        Uuid::new_v4(),

                    entity_ids: members,

                    confidence: 1.0,

                    suggested_master: None,

                    metadata:
                        Default::default(),
                }
            );
        }

        clusters
    }
}