use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct PageRequest {

    pub limit: i64,

    pub offset: i64,
}

impl Default for PageRequest {

    fn default() -> Self {

        Self {
            limit: 50,
            offset: 0,
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PageResponse<T> {

    pub data: Vec<T>,

    pub total: i64,

    pub limit: i64,

    pub offset: i64,

    pub has_next: bool,
}