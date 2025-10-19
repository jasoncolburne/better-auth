use async_trait::async_trait;
use base64::Engine;
use better_auth::interfaces::{SigningKey, VerificationKey, Verifier as VerifierTrait};
use p256::ecdsa::{
    Signature, SigningKey as P256SigningKey, VerifyingKey as P256VerifyingKey, signature::Signer,
    signature::Verifier as SigVerifier,
};

#[derive(Clone, Copy)]
pub struct Secp256r1Verifier;

impl Default for Secp256r1Verifier {
    fn default() -> Self {
        Self::new()
    }
}

impl Secp256r1Verifier {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl VerifierTrait for Secp256r1Verifier {
    async fn verify(&self, message: &str, signature: &str, public_key: &str) -> Result<(), String> {
        // Replace CESR prefix back for decoding
        let pk_bytes = base64::engine::general_purpose::URL_SAFE
            .decode(public_key)
            .map_err(|e| format!("Failed to decode public key: {}", e))?;

        // Skip 3-byte padding
        let pk_bytes = &pk_bytes[3..];

        // Import the public key
        let verifying_key = P256VerifyingKey::from_sec1_bytes(pk_bytes)
            .map_err(|e| format!("Failed to import public key: {}", e))?;

        // Replace CESR prefix back for decoding
        let sig_bytes = base64::engine::general_purpose::URL_SAFE
            .decode(signature)
            .map_err(|e| format!("Failed to decode signature: {}", e))?;

        // Skip 2-byte padding
        let sig_bytes = &sig_bytes[2..];

        // Parse as fixed-length (r,s) format
        let sig = Signature::try_from(sig_bytes)
            .map_err(|e| format!("Failed to parse signature: {}", e))?;

        verifying_key
            .verify(message.as_bytes(), &sig)
            .map_err(|_| "invalid signature".to_string())
    }
}

#[derive(Clone)]
pub struct Secp256r1 {
    key_pair: Option<P256SigningKey>,
    verifier: Secp256r1Verifier,
}

impl Default for Secp256r1 {
    fn default() -> Self {
        Self::new()
    }
}

impl Secp256r1 {
    pub fn new() -> Self {
        Self {
            key_pair: None,
            verifier: Secp256r1Verifier::new(),
        }
    }

    pub fn generate(&mut self) -> Result<(), String> {
        let signing_key = P256SigningKey::random(&mut rand::thread_rng());
        self.key_pair = Some(signing_key);
        Ok(())
    }

    fn compress_public_key(uncompressed: &[u8]) -> Result<Vec<u8>, String> {
        if uncompressed.len() != 65 {
            return Err("invalid length".to_string());
        }
        if uncompressed[0] != 0x04 {
            return Err("invalid byte header".to_string());
        }

        let x = &uncompressed[1..33];
        let y = &uncompressed[33..65];

        let y_parity = y[31] & 1;
        let prefix = if y_parity == 0 { 0x02 } else { 0x03 };

        let mut compressed = vec![prefix];
        compressed.extend_from_slice(x);

        Ok(compressed)
    }
}

#[async_trait]
impl SigningKey for Secp256r1 {
    async fn identity(&self) -> Result<String, String> {
        VerificationKey::public(self).await
    }

    async fn sign(&self, message: &str) -> Result<String, String> {
        let key_pair = self.key_pair.as_ref().ok_or("keypair not generated")?;

        let signature: Signature = key_pair.sign(message.as_bytes());
        // Use fixed-length format (r,s components, 64 bytes total for P-256)
        let sig_bytes = signature.to_bytes();

        // Prepend with 2 zero bytes for CESR encoding
        let mut padded = vec![0u8, 0u8];
        padded.extend_from_slice(&sig_bytes);

        // Base64 encode (with padding and URL-safe chars)
        let mut base64 = base64::engine::general_purpose::URL_SAFE.encode(&padded);

        // Replace first 2 characters with CESR prefix '0I'
        base64.replace_range(0..2, "0I");
        Ok(base64)
    }
}

#[async_trait]
impl VerificationKey for Secp256r1 {
    async fn public(&self) -> Result<String, String> {
        let key_pair = self.key_pair.as_ref().ok_or("keypair not generated")?;

        let verifying_key = key_pair.verifying_key();
        let encoded_point = verifying_key.to_encoded_point(false);
        let uncompressed = encoded_point.as_bytes();

        let compressed = Self::compress_public_key(uncompressed)?;

        // Prepend with 3 zero bytes for CESR encoding
        let mut padded = vec![0u8, 0u8, 0u8];
        padded.extend_from_slice(&compressed);

        // Base64 encode (with padding and URL-safe chars)
        let mut base64 = base64::engine::general_purpose::URL_SAFE.encode(&padded);

        // Replace first 4 characters with CESR prefix '1AAI'
        base64.replace_range(0..4, "1AAI");
        Ok(base64)
    }

    fn verifier(&self) -> &dyn VerifierTrait {
        &self.verifier
    }
}
