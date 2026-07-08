// Canonical Kafka topic names for Nexus MDM events.
// These constants are used when writing outbox events in mdm-core, ingest-service, etc.
// The kafka-event-service reads topic_name directly from each outbox row — it doesn't
// need to reference these constants itself.  They live here as the single authoritative list.
#![allow(dead_code)]

pub const ENTITY_CREATED:   &str = "nexus.mdm.entity.created";
pub const ENTITY_UPDATED:   &str = "nexus.mdm.entity.updated";
pub const ENTITY_DELETED:   &str = "nexus.mdm.entity.deleted";
pub const ENTITY_MERGED:    &str = "nexus.mdm.entity.merged";
pub const MATCH_APPROVED:   &str = "nexus.mdm.match.approved";
pub const MATCH_REJECTED:   &str = "nexus.mdm.match.rejected";
pub const INGEST_COMPLETED: &str = "nexus.mdm.ingest.completed";
pub const INGEST_FAILED:    &str = "nexus.mdm.ingest.failed";
pub const LINEAGE_RECORDED: &str = "nexus.mdm.lineage.recorded";
pub const CONSENT_CHANGED:  &str = "nexus.mdm.consent.changed";
pub const POLICY_EVALUATED: &str = "nexus.mdm.policy.evaluated";
pub const ANOMALY_DETECTED: &str = "nexus.mdm.anomaly.detected";
