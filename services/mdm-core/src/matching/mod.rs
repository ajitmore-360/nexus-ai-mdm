pub mod blocking;
pub mod candidate_generation;
pub mod clustering;
pub mod matcher;
pub mod models;
pub mod policy;
pub mod review;
pub mod scoring;

pub use matcher::Matcher;
pub use policy::MatchingPolicy;
