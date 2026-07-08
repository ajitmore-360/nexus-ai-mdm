use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Clone)]
pub struct DataProfileService {
    db: PgPool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AttributeProfile {
    pub attribute_name:   String,
    pub total_records:    i64,
    pub null_count:       i64,
    pub blank_count:      i64,
    pub distinct_count:   i64,
    pub null_rate:        f64,
    pub completeness_pct: f64,
    pub min_value:        Option<f64>,
    pub max_value:        Option<f64>,
    pub mean_value:       Option<f64>,
    pub stddev_value:     Option<f64>,
    pub top_values:       Value,
    pub format_patterns:  Value,
    pub outlier_ids:      Vec<Uuid>,
    pub profiled_at:      String,
}

impl DataProfileService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    /// Run profiling for all attributes of an entity type and persist results.
    /// Uses a series of SQL aggregations directly against core_mdm.entities.
    pub async fn run_profile(
        &self,
        tenant_id:   Uuid,
        entity_type: &str,
    ) -> Result<Vec<AttributeProfile>, String> {
        // 1. Get all distinct attribute keys for this entity type
        let keys_row = sqlx::query_scalar::<_, String>(
            r#"
            SELECT DISTINCT jsonb_object_keys(attributes) AS key
            FROM core_mdm.entities
            WHERE tenant_id = $1 AND entity_type = $2 AND is_deleted = false
            ORDER BY key
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .fetch_all(&self.db)
        .await
        .map_err(|e| e.to_string())?;

        let total_rows: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM core_mdm.entities WHERE tenant_id=$1 AND entity_type=$2 AND is_deleted=false",
        )
        .bind(tenant_id)
        .bind(entity_type)
        .fetch_one(&self.db)
        .await
        .map_err(|e| e.to_string())?;

        if total_rows == 0 {
            return Ok(vec![]);
        }

        let mut profiles: Vec<AttributeProfile> = Vec::new();

        for attr_key in &keys_row {
            let profile = self
                .profile_attribute(tenant_id, entity_type, attr_key, total_rows)
                .await?;
            profiles.push(profile);
        }

        Ok(profiles)
    }

    async fn profile_attribute(
        &self,
        tenant_id:    Uuid,
        entity_type:  &str,
        attr_key:     &str,
        total_records: i64,
    ) -> Result<AttributeProfile, String> {
        // Count nulls (attribute key missing) and blanks (empty string)
        let counts_row = sqlx::query(
            r#"
            SELECT
                COUNT(*) FILTER (WHERE attributes->$3 IS NULL)  AS null_count,
                COUNT(*) FILTER (WHERE attributes->>$3 = '')    AS blank_count,
                COUNT(DISTINCT attributes->>$3)
                    FILTER (WHERE attributes->$3 IS NOT NULL)   AS distinct_count
            FROM core_mdm.entities
            WHERE tenant_id=$1 AND entity_type=$2 AND is_deleted=false
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .bind(attr_key)
        .fetch_one(&self.db)
        .await
        .map_err(|e| e.to_string())?;

        let null_count:     i64 = counts_row.get("null_count");
        let blank_count:    i64 = counts_row.get("blank_count");
        let distinct_count: i64 = counts_row.get("distinct_count");

        // Numeric stats (cast attempt — NULL if non-numeric)
        let numeric_row = sqlx::query(
            r#"
            SELECT
                MIN((attributes->>$3)::double precision)    AS min_val,
                MAX((attributes->>$3)::double precision)    AS max_val,
                AVG((attributes->>$3)::double precision)    AS mean_val,
                STDDEV((attributes->>$3)::double precision) AS stddev_val
            FROM core_mdm.entities
            WHERE tenant_id=$1 AND entity_type=$2 AND is_deleted=false
              AND attributes->>$3 ~ '^-?[0-9]+(\.[0-9]+)?$'
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .bind(attr_key)
        .fetch_optional(&self.db)
        .await
        .map_err(|e| e.to_string())?;

        let (min_value, max_value, mean_value, stddev_value) =
            numeric_row.map(|r| {
                (
                    r.get::<Option<f64>, _>("min_val"),
                    r.get::<Option<f64>, _>("max_val"),
                    r.get::<Option<f64>, _>("mean_val"),
                    r.get::<Option<f64>, _>("stddev_val"),
                )
            }).unwrap_or((None, None, None, None));

        // Top 10 values by frequency
        let top_rows = sqlx::query(
            r#"
            SELECT attributes->>$3 AS val, COUNT(*) AS cnt
            FROM core_mdm.entities
            WHERE tenant_id=$1 AND entity_type=$2 AND is_deleted=false
              AND attributes->$3 IS NOT NULL AND attributes->>$3 <> ''
            GROUP BY val
            ORDER BY cnt DESC
            LIMIT 10
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .bind(attr_key)
        .fetch_all(&self.db)
        .await
        .map_err(|e| e.to_string())?;

        let top_values: Value = Value::Array(
            top_rows.iter().map(|r| {
                let val: Option<String> = r.get("val");
                let cnt: i64 = r.get("cnt");
                let pct = if total_records > 0 {
                    (cnt as f64 / total_records as f64 * 100.0).round() / 10.0 * 10.0
                } else { 0.0 };
                json!({ "value": val, "count": cnt, "pct": pct })
            }).collect(),
        );

        // Format pattern detection (extract leading char class groups)
        let pattern_rows = sqlx::query(
            r#"
            SELECT
                CASE
                    WHEN attributes->>$3 ~ '^\d{4}-\d{2}-\d{2}' THEN 'DATE(YYYY-MM-DD)'
                    WHEN attributes->>$3 ~ '^\d+$'               THEN 'INTEGER'
                    WHEN attributes->>$3 ~ '^\d+\.\d+$'          THEN 'DECIMAL'
                    WHEN attributes->>$3 ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN 'EMAIL'
                    WHEN attributes->>$3 ~ '^\+?[\d\s\-\(\)]{7,}$' THEN 'PHONE'
                    WHEN attributes->>$3 ~ '^[A-Z]{2,3}-?[0-9]+'  THEN 'CODE'
                    ELSE 'TEXT'
                END AS pattern,
                COUNT(*) AS cnt
            FROM core_mdm.entities
            WHERE tenant_id=$1 AND entity_type=$2 AND is_deleted=false
              AND attributes->$3 IS NOT NULL
            GROUP BY pattern
            ORDER BY cnt DESC
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .bind(attr_key)
        .fetch_all(&self.db)
        .await
        .map_err(|e| e.to_string())?;

        let format_patterns: Value = Value::Array(
            pattern_rows.iter().map(|r| {
                let pat: String = r.get("pattern");
                let cnt: i64 = r.get("cnt");
                let pct = if total_records > 0 { cnt as f64 / total_records as f64 * 100.0 } else { 0.0 };
                json!({ "pattern": pat, "count": cnt, "pct": (pct * 10.0).round() / 10.0 })
            }).collect(),
        );

        // Outlier detection: values beyond mean ± 3σ (numeric) or rare values <0.1%
        let outlier_rows = sqlx::query(
            r#"
            SELECT id FROM core_mdm.entities
            WHERE tenant_id=$1 AND entity_type=$2 AND is_deleted=false
              AND attributes->>$3 ~ '^-?[0-9]+(\.[0-9]+)?$'
              AND ABS((attributes->>$3)::double precision - $4) > 3 * GREATEST($5, 0.001)
            LIMIT 50
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .bind(attr_key)
        .bind(mean_value.unwrap_or(0.0))
        .bind(stddev_value.unwrap_or(0.0))
        .fetch_all(&self.db)
        .await
        .map_err(|e| e.to_string())?;

        let outlier_ids: Vec<Uuid> = outlier_rows.iter()
            .map(|r| r.get::<Uuid, _>("id"))
            .collect();

        // Persist / update profile result
        let null_rate        = if total_records > 0 { null_count as f64 / total_records as f64 * 100.0 } else { 0.0 };
        let completeness_pct = 100.0 - null_rate;

        let outlier_ids_pg: Vec<Uuid> = outlier_ids.clone();
        sqlx::query(
            r#"
            INSERT INTO core_mdm.data_profiles
                (tenant_id, entity_type, attribute_name, total_records, null_count, blank_count,
                 distinct_count, min_value, max_value, mean_value, stddev_value,
                 top_values, format_patterns, outlier_ids, profiled_at)
            VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,NOW())
            ON CONFLICT (tenant_id, entity_type, attribute_name)
            DO UPDATE SET
                total_records  = EXCLUDED.total_records,
                null_count     = EXCLUDED.null_count,
                blank_count    = EXCLUDED.blank_count,
                distinct_count = EXCLUDED.distinct_count,
                min_value      = EXCLUDED.min_value,
                max_value      = EXCLUDED.max_value,
                mean_value     = EXCLUDED.mean_value,
                stddev_value   = EXCLUDED.stddev_value,
                top_values     = EXCLUDED.top_values,
                format_patterns = EXCLUDED.format_patterns,
                outlier_ids    = EXCLUDED.outlier_ids,
                profiled_at    = NOW()
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .bind(attr_key)
        .bind(total_records)
        .bind(null_count)
        .bind(blank_count)
        .bind(distinct_count)
        .bind(min_value)
        .bind(max_value)
        .bind(mean_value)
        .bind(stddev_value)
        .bind(&top_values)
        .bind(&format_patterns)
        .bind(&outlier_ids_pg)
        .execute(&self.db)
        .await
        .map_err(|e| e.to_string())?;

        Ok(AttributeProfile {
            attribute_name:   attr_key.to_string(),
            total_records,
            null_count,
            blank_count,
            distinct_count,
            null_rate:        (null_rate * 10.0).round() / 10.0,
            completeness_pct: (completeness_pct * 10.0).round() / 10.0,
            min_value,
            max_value,
            mean_value,
            stddev_value,
            top_values,
            format_patterns,
            outlier_ids,
            profiled_at: chrono::Utc::now().to_rfc3339(),
        })
    }

    /// Fetch cached profile results for an entity type.
    pub async fn get_profile(
        &self,
        tenant_id:   Uuid,
        entity_type: &str,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT attribute_name, total_records, null_count, blank_count, distinct_count,
                   min_value, max_value, mean_value, stddev_value,
                   top_values, format_patterns, outlier_ids, profiled_at
            FROM core_mdm.data_profiles
            WHERE tenant_id=$1 AND entity_type=$2
            ORDER BY attribute_name
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| {
            let total: i64 = r.get("total_records");
            let null_c: i64 = r.get("null_count");
            let null_rate = if total > 0 { null_c as f64 / total as f64 * 100.0 } else { 0.0 };
            json!({
                "attribute_name":   r.get::<String, _>("attribute_name"),
                "total_records":    total,
                "null_count":       null_c,
                "blank_count":      r.get::<i64, _>("blank_count"),
                "distinct_count":   r.get::<i64, _>("distinct_count"),
                "null_rate":        (null_rate * 10.0).round() / 10.0,
                "completeness_pct": ((100.0 - null_rate) * 10.0).round() / 10.0,
                "min_value":        r.get::<Option<f64>, _>("min_value"),
                "max_value":        r.get::<Option<f64>, _>("max_value"),
                "mean_value":       r.get::<Option<f64>, _>("mean_value"),
                "stddev_value":     r.get::<Option<f64>, _>("stddev_value"),
                "top_values":       r.get::<Value, _>("top_values"),
                "format_patterns":  r.get::<Value, _>("format_patterns"),
                "outlier_count":    r.get::<Vec<Uuid>, _>("outlier_ids").len(),
                "profiled_at":      r.get::<chrono::DateTime<chrono::Utc>, _>("profiled_at").to_rfc3339(),
            })
        }).collect())
    }
}
