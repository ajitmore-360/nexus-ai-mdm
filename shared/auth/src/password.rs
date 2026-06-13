use anyhow::Result;

const BCRYPT_COST: u32 = 12;

/// Hash a plaintext password using bcrypt.
///
/// Cost 12 produces ~300ms hashing time on modern hardware — appropriate for
/// interactive login.  Increase to 13-14 for batch/offline attack resistance.
pub fn hash_password(password: &str) -> Result<String> {
    bcrypt::hash(password, BCRYPT_COST)
        .map_err(|e| anyhow::anyhow!("password hashing failed: {}", e))
}

/// Verify a plaintext password against a bcrypt hash.
pub fn verify_password(password: &str, hash: &str) -> Result<bool> {
    bcrypt::verify(password, hash)
        .map_err(|e| anyhow::anyhow!("password verification failed: {}", e))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_and_verify_correct_password() {
        let hash = hash_password("correct-horse-battery-staple").unwrap();
        assert!(verify_password("correct-horse-battery-staple", &hash).unwrap());
    }

    #[test]
    fn wrong_password_rejected() {
        let hash = hash_password("mypassword").unwrap();
        assert!(!verify_password("wrongpassword", &hash).unwrap());
    }

    #[test]
    fn different_hashes_for_same_password() {
        let h1 = hash_password("same").unwrap();
        let h2 = hash_password("same").unwrap();
        assert_ne!(h1, h2, "bcrypt must produce unique salts each time");
    }
}
