pub mod config;
pub mod connection;
pub mod migration;
pub mod tenant;
pub mod pagination;
pub mod pool;
pub mod rls;
pub mod transaction;
pub mod request_context;
pub mod unit_of_work;
pub mod outbox;
pub mod dead_letter;
pub mod idempotency;

// Convenience re-exports for service code
pub use pool::DbPool;
pub use request_context::{RequestContext, RequestContextFactory};
pub use unit_of_work::{PendingOutboxEvent, UnitOfWork};