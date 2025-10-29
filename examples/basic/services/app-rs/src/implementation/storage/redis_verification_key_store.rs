use super::super::crypto::Secp256r1;
use super::key_verifier::KeyVerifier;
use super::utils::get_sub_json;
use async_trait::async_trait;
use better_auth::interfaces::{Verifier, VerificationKey, VerificationKeyStore as VerificationKeyStoreTrait};
use redis::aio::ConnectionManager;
use redis::{AsyncCommands, RedisError};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Debug, Serialize, Deserialize)]
struct KeySigningPayload {
    purpose: String,
    #[serde(rename = "publicKey")]
    public_key: String,
    expiration: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct KeySigningHsm {
    identity: String,
    #[serde(rename = "generationId")]
    generation_id: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct KeySigningBody {
    payload: KeySigningPayload,
    hsm: KeySigningHsm,
}

#[derive(Debug, Serialize, Deserialize)]
struct KeySigningResponse {
    body: KeySigningBody,
    signature: String,
}

/// Redis-based VerificationKeyStore that reads public keys from Redis
pub struct RedisVerificationKeyStore {
    connection: Arc<Mutex<ConnectionManager>>,
    key_verifier: Arc<KeyVerifier>,
}

impl RedisVerificationKeyStore {
    pub fn new(connection: ConnectionManager, hsm_connection: ConnectionManager) -> Self {
        Self {
            connection: Arc::new(Mutex::new(connection)),
            key_verifier: Arc::new(KeyVerifier::new(hsm_connection)),
        }
    }
}

#[async_trait]
impl VerificationKeyStoreTrait for RedisVerificationKeyStore {
    async fn get(&self, identity: &str) -> Result<Box<dyn VerificationKey>, String> {
        // Retry logic to handle Redis reconnection after restart
        const MAX_RETRIES: u32 = 3;
        const INITIAL_BACKOFF_MS: u64 = 100;

        let mut last_error = None;

        for attempt in 0..MAX_RETRIES {
            if attempt > 0 {
                // Exponential backoff
                let backoff_ms = INITIAL_BACKOFF_MS * 2_u64.pow(attempt - 1);
                tokio::time::sleep(tokio::time::Duration::from_millis(backoff_ms)).await;
            }

            let mut conn = self.connection.lock().await;

            // Get the HSM response from Redis
            let result: Result<String, RedisError> = conn.get(identity).await;
            match result {
                Ok(value) => {
                    // Successfully got value, continue with processing
                    return self.process_response(&value).await;
                }
                Err(e) => {
                    last_error = Some(format!("Redis error: {}", e));
                    // Drop the lock before retrying to allow reconnection
                    drop(conn);
                    continue;
                }
            }
        }

        Err(last_error.unwrap_or_else(|| "Redis connection failed after retries".to_string()))
    }
}

impl RedisVerificationKeyStore {
    async fn process_response(&self, value: &str) -> Result<Box<dyn VerificationKey>, String> {
        // Parse the response structure
        let response: KeySigningResponse = serde_json::from_str(value)
            .map_err(|e| format!("failed to parse response: {}", e))?;

        // Extract raw body JSON for signature verification
        let body_json = get_sub_json(value, "body")?;

        // Verify HSM signature using KeyVerifier
        self.key_verifier.verify(
            &response.signature,
            &response.body.hsm.identity,
            &response.body.hsm.generation_id,
            &body_json,
        ).await?;

        // Validate purpose
        if response.body.payload.purpose != "access" {
            return Err(format!("invalid purpose: expected access, got {}", response.body.payload.purpose));
        }

        // Check expiration
        let expiration = chrono::DateTime::parse_from_rfc3339(&response.body.payload.expiration)
            .map_err(|e| format!("failed to parse expiration: {}", e))?;
        if expiration <= chrono::Utc::now() {
            return Err("key expired".to_string());
        }

        // Return the public key from the payload
        Ok(Box::new(PublicKeyWrapper {
            public_key: response.body.payload.public_key
        }) as Box<dyn VerificationKey>)
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
