// Canonical Kafka topic names for Nexus MDM events.
// These constants are used when writing outbox events in mdm-core, ingest-service, etc.
// The kafka-event-service reads topic_name directly from each outbox row â€” it doesn't
// need to reference these constants itself.  They live here as the single authoritative list.
#![allow(dead_code)]

pub const ENTITY_CREATED:   &str = "azile.mdm.entity.created";
pub const ENTITY_UPDATED:   &str = "azile.mdm.entity.updated";
pub const ENTITY_DELETED:   &str = "azile.mdm.entity.deleted";
pub const ENTITY_MERGED:    &str = "azile.mdm.entity.merged";
pub const MATCH_APPROVED:   &str = "azile.mdm.match.approved";
pub const MATCH_REJECTED:   &str = "azile.mdm.match.rejected";
pub const INGEST_COMPLETED: &str = "azile.mdm.ingest.completed";
pub const INGEST_FAILED:    &str = "azile.mdm.ingest.failed";
pub const LINEAGE_RECORDED: &str = "azile.mdm.lineage.recorded";
pub const CONSENT_CHANGED:  &str = "azile.mdm.consent.changed";
pub const POLICY_EVALUATED: &str = "azile.mdm.policy.evaluated";
pub const ANOMALY_DETECTED: &str = "azile.mdm.anomaly.detected";
