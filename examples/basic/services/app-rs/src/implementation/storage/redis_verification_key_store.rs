use super::super::crypto::Secp256r1;
use async_trait::async_trait;
use better_auth::interfaces::{VerificationKey, VerificationKeyStore as VerificationKeyStoreTrait};
use redis::aio::ConnectionManager;
use redis::{AsyncCommands, RedisError};
use std::sync::Arc;
use tokio::sync::Mutex;

/// Redis-based VerificationKeyStore that reads public keys from Redis
pub struct RedisVerificationKeyStore {
    connection: Arc<Mutex<ConnectionManager>>,
}

impl RedisVerificationKeyStore {
    pub fn new(connection: ConnectionManager) -> Self {
        Self {
            connection: Arc::new(Mutex::new(connection)),
        }
    }
}

#[async_trait]
impl VerificationKeyStoreTrait for RedisVerificationKeyStore {
    async fn get(&self, identity: &str) -> Result<Box<dyn VerificationKey>, String> {
        let mut conn = self.connection.lock().await;

        // Get the public key from Redis
        let public_key: String = conn
            .get(identity)
            .await
            .map_err(|e: RedisError| format!("Redis error: {}", e))?;

        // Create a Secp256r1 key from the public key
        // Note: We can't directly instantiate a verification-only key with p256,
        // but we can create a wrapper that implements VerificationKey
        Ok(Box::new(PublicKeyWrapper { public_key }) as Box<dyn VerificationKey>)
    }
}

/// Wrapper for a public key string that implements VerificationKey
struct PublicKeyWrapper {
    public_key: String,
}

#[async_trait]
impl VerificationKey for PublicKeyWrapper {
    async fn public(&self) -> Result<String, String> {
        Ok(self.public_key.clone())
    }

    fn verifier(&self) -> &dyn better_auth::interfaces::Verifier {
        // Return a static verifier instance
        &Secp256r1VerifierStatic
    }
}

/// A static verifier for use in PublicKeyWrapper
struct Secp256r1VerifierStatic;

#[async_trait]
impl better_auth::interfaces::Verifier for Secp256r1VerifierStatic {
    async fn verify(&self, message: &str, signature: &str, public_key: &str) -> Result<(), String> {
        use base64::Engine;
        use p256::ecdsa::{
            Signature, VerifyingKey as P256VerifyingKey, signature::Verifier as SigVerifier,
        };

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
