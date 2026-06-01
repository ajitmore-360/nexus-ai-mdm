use chrono::{DateTime, Utc};

use serde::{
    Deserialize,
    Serialize,
};

#[derive(Debug, Serialize, Deserialize)]
pub struct CursorPageRequest {

    pub cursor: Option<DateTime<Utc>>,

    pub limit: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CursorPageResponse<T> {

    pub data: Vec<T>,

    pub next_cursor:
        Option<DateTime<Utc>>,

    pub has_next: bool,
}