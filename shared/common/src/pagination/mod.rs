use serde::{
    Deserialize,
    Serialize,
};

#[derive(Debug, Clone, Deserialize)]
pub struct PageRequest {

    pub page: Option<u64>,

    pub page_size: Option<u64>,
}

impl PageRequest {

    pub fn normalized_page(&self) -> u64 {

        self.page.unwrap_or(1)
    }

    pub fn normalized_page_size(&self) -> u64 {

        self.page_size
            .unwrap_or(25)
            .min(100)
    }

    pub fn offset(&self) -> u64 {

        (
            self.normalized_page() - 1
        )
        * self.normalized_page_size()
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct PageResponse<T> {

    pub items: Vec<T>,

    pub total: u64,

    pub page: u64,

    pub page_size: u64,

    pub has_next: bool,
}