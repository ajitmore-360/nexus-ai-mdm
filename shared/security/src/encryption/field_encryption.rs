use aes_gcm::{
    Aes256Gcm,
    Key,
    Nonce,
};

use aes_gcm::aead::{
    Aead,
    KeyInit,
};

use base64::{
    engine::general_purpose,
    Engine as _,
};

use rand::RngCore;

pub struct FieldEncryptionService {

    cipher: Aes256Gcm,
}

impl FieldEncryptionService {

    pub fn new(
        key_bytes: &[u8; 32]
    ) -> Self {

        let key =
            Key::<Aes256Gcm>::from_slice(
                key_bytes
            );

        let cipher =
            Aes256Gcm::new(key);

        Self {
            cipher
        }
    }

    pub fn encrypt(
        &self,
        plaintext: &str,
    ) -> anyhow::Result<String> {

        let mut nonce_bytes =
            [0u8; 12];

        rand::thread_rng()
            .fill_bytes(
                &mut nonce_bytes
            );

        let nonce =
            Nonce::from_slice(
                &nonce_bytes
            );

        let ciphertext =
            self
                .cipher
                .encrypt(
                    nonce,
                    plaintext.as_bytes()
                )
                .map_err(|_| anyhow::anyhow!("AES-GCM encryption failed"))?;

        let mut combined =
            nonce_bytes.to_vec();

        combined.extend(ciphertext);

        Ok(
            general_purpose::STANDARD
                .encode(combined)
        )
    }

    pub fn decrypt(
        &self,
        value: &str,
    ) -> anyhow::Result<String> {

        let bytes =
            general_purpose::STANDARD
                .decode(value)?;

        let (nonce_bytes, cipher_bytes) =
            bytes.split_at(12);

        let nonce =
            Nonce::from_slice(
                nonce_bytes
            );

        let plaintext =
            self
                .cipher
                .decrypt(
                    nonce,
                    cipher_bytes
                )
                .map_err(|_| anyhow::anyhow!("AES-GCM decryption failed (wrong key or corrupted ciphertext)"))?;

        Ok(
            String::from_utf8(
                plaintext
            )?
        )
    }
}