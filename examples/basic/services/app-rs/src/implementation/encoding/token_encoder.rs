use async_trait::async_trait;
use base64::Engine;
use better_auth::interfaces::TokenEncoder as TokenEncoderTrait;
use flate2::Compression;
use flate2::read::GzDecoder;
use flate2::write::GzEncoder;
use std::io::Write;

pub struct TokenEncoder;

impl Default for TokenEncoder {
    fn default() -> Self {
        Self::new()
    }
}

impl TokenEncoder {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl TokenEncoderTrait for TokenEncoder {
    async fn signature_length(&self, token: &str) -> Result<usize, String> {
        if token.len() < 88 {
            return Err("token too short".to_string());
        }

        if !token.starts_with("0I") {
            return Err("incorrect token format".to_string());
        }

        Ok(88)
    }

    async fn encode(&self, object: &str) -> Result<String, String> {
        // Compress with gzip at level 9
        let mut encoder = GzEncoder::new(Vec::new(), Compression::best());
        encoder
            .write_all(object.as_bytes())
            .map_err(|e| format!("Failed to write to gzip encoder: {}", e))?;
        let compressed = encoder
            .finish()
            .map_err(|e| format!("Failed to finish gzip encoding: {}", e))?;

        // Encode to URL-safe base64 without padding
        let base64 = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(&compressed);

        Ok(base64)
    }

    async fn decode(&self, raw_token: &str) -> Result<String, String> {
        use std::io::Read;

        // The token uses URL-safe base64 encoding without padding
        // We can decode directly with NO_PAD or add padding back manually
        // Try with NO_PAD first, if that fails add padding
        let compressed = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(raw_token)
            .or_else(|_| {
                // Add padding if needed
                let mut padded = raw_token.to_string();
                while !padded.len().is_multiple_of(4) {
                    padded.push('=');
                }
                base64::engine::general_purpose::URL_SAFE.decode(padded)
            })
            .map_err(|e| format!("Failed to decode base64: {}", e))?;

        // Decompress with gzip
        let decoder = GzDecoder::new(&compressed[..]);
        let mut decompressed = Vec::new();
        let mut decoder = decoder;
        decoder
            .read_to_end(&mut decompressed)
            .map_err(|e| format!("Failed to read decompressed data: {}", e))?;

        // Convert to string
        String::from_utf8(decompressed).map_err(|e| format!("Failed to convert to UTF-8: {}", e))
    }
}
