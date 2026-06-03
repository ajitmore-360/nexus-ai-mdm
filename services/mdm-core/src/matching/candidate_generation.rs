use std::collections::{
    HashMap,
    HashSet,
};

use anyhow::Result;
use tracing::{
    debug,
    info,
    instrument,
};
use uuid::Uuid;

use shared_contracts::mdm::{
    entity::CanonicalEntity,
    matching::{
        BlockingDiagnostics,
        MatchRequest,
    },
};

use crate::{
    db::repositories::matching_repository::MatchingRepository,
    matching::{
        blocking::{
            canopy::CanopyBlocker,
            phonetics::PhoneticBlocker,
            vector_blocking::VectorBlocker,
        },
        models::{
            BlockingResult,
            CandidateEntity,
        },
    },
};

//
// ======================================================
// CANDIDATE GENERATOR
// ======================================================
//

pub struct CandidateGenerator<R>
where
    R: MatchingRepository,
{
    repository: R,

    phonetic_blocker: PhoneticBlocker,

    canopy_blocker: CanopyBlocker,

    vector_blocker: VectorBlocker,
}

impl<R> CandidateGenerator<R>
where
    R: MatchingRepository,
{
    pub fn new(
        repository: R,
        phonetic_blocker: PhoneticBlocker,
        canopy_blocker: CanopyBlocker,
        vector_blocker: VectorBlocker,
    ) -> Self {
        Self {
            repository,
            phonetic_blocker,
            canopy_blocker,
            vector_blocker,
        }
    }

    //
    // ==================================================
    // GENERATE
    // ==================================================
    //

    #[instrument(skip(self, request))]
    pub async fn generate_candidates(
        &self,
        request: &MatchRequest,
    ) -> Result<BlockingResult> {

        let mut candidate_ids =
            HashSet::<Uuid>::new();

        let mut generated_keys =
            Vec::<String>::new();

        let mut applied_rules =
            Vec::<String>::new();

        //
        // ==============================================
        // Exact deterministic blocking
        // ==============================================
        //

        let exact_keys =
            self.generate_exact_keys(
                &request.entity,
            );

        generated_keys.extend(
            exact_keys.clone(),
        );

        applied_rules.push(
            "deterministic".to_string(),
        );

        let exact_matches =
            self.repository
                .find_by_blocking_keys(
                    request.tenant_id,
                    &exact_keys,
                    request.max_candidates,
                )
                .await?;

        candidate_ids.extend(exact_matches);

        //
        // ==============================================
        // Phonetic blocking
        // ==============================================
        //

        let phonetic_keys =
            self.phonetic_blocker
                .generate_keys(
                    &request.entity,
                );

        generated_keys.extend(
            phonetic_keys.clone(),
        );

        applied_rules.push(
            "phonetic".to_string(),
        );

        let phonetic_matches =
            self.repository
                .find_by_blocking_keys(
                    request.tenant_id,
                    &phonetic_keys,
                    request.max_candidates,
                )
                .await?;

        candidate_ids.extend(
            phonetic_matches,
        );

        //
        // ==============================================
        // Canopy blocking
        // ==============================================
        //

        let canopy_candidates =
            self.canopy_blocker
                .find_candidates(
                    request.tenant_id,
                    &request.entity,
                )
                .await?;

        applied_rules.push(
            "canopy".to_string(),
        );

        candidate_ids.extend(
            canopy_candidates,
        );

        //
        // ==============================================
        // Vector blocking
        // ==============================================
        //

        if request.semantic_matching {

            let vector_candidates =
                self.vector_blocker
                    .find_candidates(
                        request.tenant_id,
                        &request.entity,
                    )
                    .await?;

            applied_rules.push(
                "vector".to_string(),
            );

            candidate_ids.extend(
                vector_candidates,
            );
        }

        //
        // Remove self-match
        //

        candidate_ids.remove(
            &request.entity.entity_id,
        );

        //
        // Candidate cap
        //

        if candidate_ids.len()
            > request.max_candidates
        {
            candidate_ids =
                candidate_ids
                    .into_iter()
                    .take(
                        request.max_candidates,
                    )
                    .collect();
        }

        info!(
            tenant_id=%request.tenant_id,
            generated_candidates=%candidate_ids.len(),
            "candidate generation completed"
        );

        Ok(
            BlockingResult {
                candidate_ids:
                    candidate_ids.clone(),

                diagnostics:
                    BlockingDiagnostics {

                        applied_rules,

                        generated_keys,

                        reduced_candidates:
                            candidate_ids.len(),

                        metadata:
                            HashMap::new(),
                    },
            }
        )
    }

    //
    // ==================================================
    // LOAD FULL ENTITIES
    // ==================================================
    //

    #[instrument(skip(self))]
    pub async fn load_entities(
        &self,
        tenant_id: Uuid,
        candidate_ids: &HashSet<Uuid>,
    ) -> Result<
        Vec<CandidateEntity>
    > {

        let entities =
            self.repository
                .load_entities(
                    tenant_id,
                    candidate_ids,
                )
                .await?;

        let result =
            entities
                .into_iter()
                .map(
                    |entity| CandidateEntity {

                        entity,

                        blocking_score: 1.0,
                    }
                )
                .collect();

        Ok(result)
    }

    //
    // ==================================================
    // EXACT BLOCK KEYS
    // ==================================================
    //

    fn generate_exact_keys(
        &self,
        entity: &CanonicalEntity,
    ) -> Vec<String> {

        let mut keys =
            Vec::new();

        for attr in &entity.attributes {

            let field =
                attr.key.to_lowercase();

            let value =
                attr.value
                    .as_str()
                    .unwrap_or("")
                    .trim()
                    .to_lowercase();

            if value.is_empty() {
                continue;
            }

            match field.as_str() {

                "email" => {
                    keys.push(
                        format!(
                            "EMAIL:{}",
                            value
                        )
                    );
                }

                "phone" => {
                    keys.push(
                        format!(
                            "PHONE:{}",
                            value
                                .replace(
                                    "-",
                                    "",
                                )
                        )
                    );
                }

                "tax_id" => {
                    keys.push(
                        format!(
                            "TAX:{}",
                            value
                        )
                    );
                }

                "customer_id" => {
                    keys.push(
                        format!(
                            "CID:{}",
                            value
                        )
                    );
                }

                "vendor_id" => {
                    keys.push(
                        format!(
                            "VID:{}",
                            value
                        )
                    );
                }

                _ => {}
            }
        }

        debug!(
            generated_keys=?keys,
            "exact blocking keys generated"
        );

        keys
    }
}