use base64::Engine;
use blake3::Hasher as Blake3;

/// Blake3 hasher that produces CESR-encoded hashes
pub struct Blake3Hasher;

impl Blake3Hasher {
    pub fn new() -> Self {
        Self
    }

    /// Compute a CESR-encoded Blake3 hash of the input
    ///
    /// Returns a base64url-encoded string with 'E' prefix (CESR format)
    pub fn sum(&self, message: &str) -> String {
        let hash_bytes = Blake3::new()
            .update(message.as_bytes())
            .finalize();

        // Add leading zero byte for CESR padding
        let mut padded = vec![0u8];
        padded.extend_from_slice(hash_bytes.as_bytes());

        // Encode to base64url
        let base64 = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(&padded);

        // Replace first character with 'E' for CESR prefix
        format!("E{}", &base64[1..])
    }
}

impl Default for Blake3Hasher {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_blake3_hasher() {
        let hasher = Blake3Hasher::new();
        let hash = hasher.sum("test message");

        // Should start with 'E' prefix
        assert!(hash.starts_with('E'));

        // Should be base64url encoded (44 chars for 32-byte hash + 1 byte padding)
        assert_eq!(hash.len(), 44);
    }

    #[test]
    fn test_blake3_hasher_consistent() {
        let hasher = Blake3Hasher::new();
        let hash1 = hasher.sum("test");
        let hash2 = hasher.sum("test");

        // Same input should produce same hash
        assert_eq!(hash1, hash2);
    }

    #[test]
    fn test_blake3_hasher_different_inputs() {
        let hasher = Blake3Hasher::new();
        let hash1 = hasher.sum("test1");
        let hash2 = hasher.sum("test2");

        // Different inputs should produce different hashes
        assert_ne!(hash1, hash2);
    }
}
