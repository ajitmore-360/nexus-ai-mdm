use anyhow::Result;
use serde::Deserialize;
use serde_json::Value;
use uuid::Uuid;

use crate::anomaly::AnomalyDetector;

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub struct DetectAnomaliesArgs {
    pub entity_type: Option<String>,
}

/// Run the anomaly detector and return structured results for the copilot.
pub async fn detect_anomalies(
    detector:  &AnomalyDetector,
    tenant_id: Uuid,
    _args:     DetectAnomaliesArgs,
) -> Result<Value> {
    let anomalies = detector.scan(tenant_id).await?;

    let critical = anomalies.iter().filter(|a| matches!(a.severity, crate::anomaly::AnomalySeverity::Critical)).count();
    let high     = anomalies.iter().filter(|a| matches!(a.severity, crate::anomaly::AnomalySeverity::High)).count();

    Ok(serde_json::json!({
        "tenant_id":     tenant_id,
        "anomaly_count": anomalies.len(),
        "critical":      critical,
        "high":          high,
        "anomalies":     anomalies,
        "scanned_at":    chrono::Utc::now(),
    }))
}
