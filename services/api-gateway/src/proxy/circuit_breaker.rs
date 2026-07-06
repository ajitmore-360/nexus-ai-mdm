use std::sync::atomic::{AtomicI64, AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

/// Per-upstream circuit breaker with three states:
///
/// - **Closed** (normal): requests pass through; failures are counted.
/// - **Open** (tripped): requests are rejected immediately until `open_duration_secs` has elapsed.
/// - **Half-open** (probe): one request is allowed through. Success closes the circuit; failure
///   re-opens it for another `open_duration_secs`.
///
/// All state is stored in atomics — no mutex needed for the fast path.
pub struct CircuitBreaker {
    /// Consecutive failures that trigger the open state.
    failure_threshold: u64,
    /// How many seconds the circuit stays open before entering half-open.
    open_duration_secs: i64,
    consecutive_failures: AtomicU64,
    /// Unix timestamp (seconds) when the circuit most recently opened; 0 = closed/half-open.
    opened_at: AtomicI64,
}

impl CircuitBreaker {
    pub fn new(failure_threshold: u64, open_duration_secs: u64) -> Self {
        Self {
            failure_threshold,
            open_duration_secs: open_duration_secs as i64,
            consecutive_failures: AtomicU64::new(0),
            opened_at: AtomicI64::new(0),
        }
    }

    fn now_secs() -> i64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64
    }

    /// Returns `true` if the circuit is fully open and the caller should fail-fast.
    /// Returns `false` if closed or half-open (probe allowed).
    pub fn is_open(&self) -> bool {
        let failures = self.consecutive_failures.load(Ordering::Relaxed);
        if failures < self.failure_threshold {
            return false;
        }
        let opened = self.opened_at.load(Ordering::Relaxed);
        if opened == 0 {
            return false; // half-open or just reset
        }
        Self::now_secs() - opened < self.open_duration_secs
    }

    /// Call after a successful upstream response.
    pub fn record_success(&self) {
        self.consecutive_failures.store(0, Ordering::Relaxed);
        self.opened_at.store(0, Ordering::Relaxed);
    }

    /// Call after a failed upstream response (network error or 5xx).
    pub fn record_failure(&self) {
        let prev = self.consecutive_failures.fetch_add(1, Ordering::Relaxed);
        if prev + 1 >= self.failure_threshold {
            // Transition from closed to open — only stamp the time once per trip.
            let _ = self.opened_at.compare_exchange(
                0,
                Self::now_secs(),
                Ordering::Relaxed,
                Ordering::Relaxed,
            );
        }
    }
}
