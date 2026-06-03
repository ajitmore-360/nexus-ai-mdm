use std::time::Duration;

use anyhow::Result;
use tokio::time::sleep;
use tracing::{
    error,
    warn,
};

#[derive(Clone)]
pub struct RetryPolicy {

    pub max_attempts: u32,

    pub initial_delay_ms: u64,

    pub max_delay_ms: u64,

    pub exponential_multiplier: f64,
}

impl Default for RetryPolicy {

    fn default() -> Self {

        Self {

            max_attempts: 5,

            initial_delay_ms: 250,

            max_delay_ms: 10_000,

            exponential_multiplier: 2.0,
        }
    }
}

pub async fn retry_async<F, Fut, T>(
    operation_name: &str,
    policy: &RetryPolicy,
    mut operation: F,
) -> Result<T>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<
        Output = Result<T>,
    >,
{
    let mut attempt = 1u32;

    let mut delay =
        policy.initial_delay_ms;

    loop {

        match operation().await {

            Ok(result) => {

                if attempt > 1 {

                    warn!(
                        operation=%operation_name,
                        attempts=%attempt,
                        "operation succeeded after retry"
                    );
                }

                return Ok(result);
            }

            Err(error) => {

                if attempt >= policy.max_attempts {

                    error!(
                        operation=%operation_name,
                        attempts=%attempt,
                        error=?error,
                        "retry exhausted"
                    );

                    return Err(error);
                }

                warn!(
                    operation=%operation_name,
                    attempt=%attempt,
                    next_delay_ms=%delay,
                    error=?error,
                    "retrying operation"
                );

                sleep(
                    Duration::from_millis(delay)
                ).await;

                delay = ((delay as f64)
                    * policy.exponential_multiplier)
                    as u64;

                delay =
                    delay.min(
                        policy.max_delay_ms
                    );

                attempt += 1;
            }
        }
    }
}

pub async fn retry_db<F, Fut, T>(
    operation: F,
) -> Result<T>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<
        Output = Result<T>,
    >,
{
    retry_async(
        "database",
        &RetryPolicy {
            max_attempts: 3,
            initial_delay_ms: 100,
            max_delay_ms: 2_000,
            exponential_multiplier: 2.0,
        },
        operation,
    )
    .await
}

pub async fn retry_kafka<F, Fut, T>(
    operation: F,
) -> Result<T>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<
        Output = Result<T>,
    >,
{
    retry_async(
        "kafka",
        &RetryPolicy {
            max_attempts: 10,
            initial_delay_ms: 500,
            max_delay_ms: 30_000,
            exponential_multiplier: 2.0,
        },
        operation,
    )
    .await
}

pub async fn retry_ai<F, Fut, T>(
    operation: F,
) -> Result<T>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<
        Output = Result<T>,
    >,
{
    retry_async(
        "ai-service",
        &RetryPolicy {
            max_attempts: 4,
            initial_delay_ms: 1000,
            max_delay_ms: 20000,
            exponential_multiplier: 2.0,
        },
        operation,
    )
    .await
}