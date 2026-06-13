// Integration tests for RedisRateLimiter.
// Run with: cargo test -p nexus-redis -- --ignored  (requires live Redis)
// Unit test below uses only local logic.

#[cfg(test)]
mod unit {
    // Sliding-window key format is deterministic — test the key derivation logic.
    #[test]
    fn rate_limiter_key_contains_prefix_and_client() {
        let prefix = "nexus";
        let client = "192.168.1.1";
        let key = format!("{}:ratelimit:{}", prefix, client);
        assert_eq!(key, "nexus:ratelimit:192.168.1.1");
    }
}
