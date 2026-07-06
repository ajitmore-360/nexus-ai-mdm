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

#[cfg(test)]
mod seed_hash_check {
    #[test]
    fn migration_0009_hash_is_valid() {
        let hash = "$2b$12$lbLU3nX07tDW6kETsyEIzeAJGnWwdkGK5p5LJs422uB4EJVqIUpJy";
        let ok = bcrypt::verify("Admin@123", hash).expect("bcrypt::verify must not error");
        assert!(ok, "migration 0009 hardcoded hash must verify Admin@123");
    }
}
