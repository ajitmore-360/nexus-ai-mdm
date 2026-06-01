use chrono::{
    DateTime,
    Utc,
};

pub fn build_cursor_query(
    base: &str,
    cursor: Option<DateTime<Utc>>,
    limit: i64,
) -> String {

    match cursor {

        Some(cursor) => {

            format!(
                "
                {}
                AND created_at < '{}'
                ORDER BY created_at DESC
                LIMIT {}
                ",
                base,
                cursor.to_rfc3339(),
                limit
            )
        }

        None => {

            format!(
                "
                {}
                ORDER BY created_at DESC
                LIMIT {}
                ",
                base,
                limit
            )
        }
    }
}