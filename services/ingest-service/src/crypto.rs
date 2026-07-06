/// AES-256-GCM encryption for connection credentials stored as JSONB.
///
/// If `CONNECTION_CONFIG_KEY` is absent (dev), values are stored as-is.
/// When set it must be a base64-encoded 32-byte key (≈ 44 base64 chars).
///
/// Encrypted values are wrapped: `{"_encrypted":"enc:v1:<base64(nonce||ct)>"}`
/// so they remain valid JSONB while being clearly marked as ciphertext.
use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use rand::RngCore;

const PREFIX: &str = "enc:v1:";
const NONCE_LEN: usize = 12;
const ENC_KEY: &str = "_encrypted";

fn load_key() -> Option<[u8; 32]> {
    let b64 = std::env::var("CONNECTION_CONFIG_KEY").ok()?;
    let bytes = B64.decode(b64.trim()).ok()?;
    if bytes.len() != 32 {
        tracing::warn!(
            "CONNECTION_CONFIG_KEY must decode to 32 bytes (got {}); storing plaintext.",
            bytes.len()
        );
        return None;
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Some(key)
}

/// Encrypt `value` and return a JSONB-safe JSON Value.
/// Returns the original value unchanged if no key is configured.
pub fn encrypt_config(value: &serde_json::Value) -> serde_json::Value {
    let Some(key_bytes) = load_key() else {
        return value.clone();
    };

    let plaintext = value.to_string();
    let cipher = Aes256Gcm::new_from_slice(&key_bytes).expect("key is 32 bytes");

    let mut nonce_bytes = [0u8; NONCE_LEN];
    rand::rngs::OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(nonce, plaintext.as_bytes())
        .expect("AES-GCM encryption");

    let mut blob = Vec::with_capacity(NONCE_LEN + ciphertext.len());
    blob.extend_from_slice(&nonce_bytes);
    blob.extend_from_slice(&ciphertext);

    serde_json::json!({ ENC_KEY: format!("{}{}", PREFIX, B64.encode(&blob)) })
}

/// Decrypt a stored JSONB value.
/// If the value has an `_encrypted` key it is decrypted; otherwise returned as-is.
pub fn decrypt_config(value: &serde_json::Value) -> serde_json::Value {
    let Some(enc_str) = value.get(ENC_KEY).and_then(|v| v.as_str()) else {
        return value.clone();
    };

    if !enc_str.starts_with(PREFIX) {
        return value.clone();
    }

    let Some(key_bytes) = load_key() else {
        tracing::warn!("Encrypted connection_config found but CONNECTION_CONFIG_KEY not set");
        return serde_json::json!({});
    };

    let blob = match B64.decode(&enc_str[PREFIX.len()..]) {
        Ok(b) => b,
        Err(_) => return serde_json::json!({}),
    };

    if blob.len() < NONCE_LEN {
        return serde_json::json!({});
    }

    let (nonce_bytes, ct) = blob.split_at(NONCE_LEN);
    let cipher = Aes256Gcm::new_from_slice(&key_bytes).expect("key is 32 bytes");
    let nonce  = Nonce::from_slice(nonce_bytes);

    match cipher.decrypt(nonce, ct) {
        Ok(plain) => serde_json::from_slice(&plain).unwrap_or(serde_json::json!({})),
        Err(_) => {
            tracing::error!("AES-GCM decryption failed");
            serde_json::json!({})
        }
    }
}
