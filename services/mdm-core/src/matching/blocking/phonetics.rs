use std::collections::HashSet;
use std::sync::Arc;

use async_trait::async_trait;
use uuid::Uuid;

use contracts::mdm::entity::{CanonicalEntity, EntityAttribute};

use crate::db::repositories::matching_repository::MatchingRepository;
use crate::matching::blocking::strategy::BlockingStrategy;

/// Stop words excluded from phonetic key generation for company/person names.
const STOP_WORDS: &[&str] = &[
    "the", "of", "and", "a", "an",
    "inc", "incorporated", "llc", "ltd", "limited",
    "corp", "corporation", "co", "company",
    "plc", "gmbh", "ag", "sa", "bv", "nv",
];

/// Compute the American Soundex code for a single word.
/// Returns a 4-character code: first letter + 3 digits.
fn soundex(word: &str) -> Option<String> {
    let word = word.to_uppercase();
    let letters: Vec<char> = word.chars().filter(|c| c.is_ascii_alphabetic()).collect();
    if letters.is_empty() {
        return None;
    }

    let code_for = |c: char| -> u8 {
        match c {
            'B' | 'F' | 'P' | 'V'             => 1,
            'C' | 'G' | 'J' | 'K' | 'Q'
            | 'S' | 'X' | 'Z'                  => 2,
            'D' | 'T'                           => 3,
            'L'                                 => 4,
            'M' | 'N'                           => 5,
            'R'                                 => 6,
            _                                   => 0, // A E I O U H W Y
        }
    };

    let first = letters[0];
    let mut code = String::with_capacity(4);
    code.push(first);

    let mut prev = code_for(first);

    for &c in &letters[1..] {
        let digit = code_for(c);
        if digit == 0 || digit == prev {
            // vowels and H/W act as separators but don't add digits;
            // skip duplicate adjacent codes
            if digit == 0 {
                prev = 0; // vowel resets separator so next same-code letter is NOT skipped
            }
            continue;
        }
        code.push(char::from_digit(digit as u32, 10).unwrap_or('0'));
        prev = digit;
        if code.len() == 4 {
            break;
        }
    }

    while code.len() < 4 {
        code.push('0');
    }

    Some(code)
}

pub struct PhoneticBlocker {
    repository: Arc<MatchingRepository>,
}

impl PhoneticBlocker {
    pub fn new(repository: Arc<MatchingRepository>) -> Self {
        Self { repository }
    }

    /// Generate Soundex-based phonetic blocking keys from a slice of entity attributes.
    /// Each significant name word produces one key: `PHONETIC:<SOUNDEX_CODE>`.
    /// `pub(crate)` so entity_repository can populate the blocking_keys table on create/update.
    pub(crate) fn generate_keys_from_attrs(attrs: &[EntityAttribute]) -> Vec<String> {
        let mut keys = HashSet::new();

        for attr in attrs {
            let field = attr.key.to_lowercase();
            if !matches!(field.as_str(), "name" | "company_name" | "legal_name" | "full_name") {
                continue;
            }

            let value = attr.value.as_str().unwrap_or("").trim().to_lowercase();
            if value.is_empty() {
                continue;
            }

            for word in value.split_whitespace() {
                let clean: String = word.chars().filter(|c| c.is_ascii_alphabetic()).collect();
                if clean.len() < 2 || STOP_WORDS.contains(&clean.as_str()) {
                    continue;
                }
                if let Some(code) = soundex(&clean) {
                    keys.insert(format!("PHONETIC:{code}"));
                }
            }
        }

        keys.into_iter().collect()
    }

    /// Convenience wrapper that accepts a full entity.
    pub(crate) fn generate_keys(entity: &CanonicalEntity) -> Vec<String> {
        Self::generate_keys_from_attrs(&entity.attributes)
    }
}

#[async_trait]
impl BlockingStrategy for PhoneticBlocker {
    fn name(&self) -> &'static str {
        "phonetic"
    }

    async fn find_candidates(
        &self,
        tenant_id: Uuid,
        entity: &CanonicalEntity,
    ) -> anyhow::Result<HashSet<Uuid>> {
        let keys = Self::generate_keys(entity);

        if keys.is_empty() {
            return Ok(HashSet::new());
        }

        let candidates = self
            .repository
            .find_by_blocking_keys(tenant_id, &keys, 500)
            .await?;

        Ok(candidates)
    }
}
