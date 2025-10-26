use super::super::crypto::Secp256r1;
use async_trait::async_trait;
use better_auth::interfaces::{Verifier, VerificationKey, VerificationKeyStore as VerificationKeyStoreTrait};
use redis::aio::ConnectionManager;
use redis::{AsyncCommands, RedisError};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::Mutex;

const HSM_PUBLIC_KEY: &str = "1AAIAjIhd42fcH957TzvXeMbgX4AftiTT7lKmkJ7yHy3dph9";

#[derive(Debug, Serialize, Deserialize)]
struct HsmResponsePayload {
    purpose: String,
    #[serde(rename = "publicKey")]
    public_key: String,
    expiration: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct HsmResponseBody {
    payload: HsmResponsePayload,
    #[serde(rename = "hsmIdentity")]
    hsm_identity: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct HsmResponse {
    body: HsmResponseBody,
    signature: String,
}

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

        // Get the HSM response from Redis
        let value: String = conn
            .get(identity)
            .await
            .map_err(|e: RedisError| format!("Redis error: {}", e))?;

        // Extract the raw body JSON substring without re-encoding
        let body_start = value.find("\"body\":").ok_or("missing body in HSM response")?
            + "\"body\":".len();

        let mut brace_count = 0;
        let mut in_body = false;
        let mut body_end = None;

        for (i, ch) in value[body_start..].chars().enumerate() {
            let idx = body_start + i;
            match ch {
                '{' => {
                    in_body = true;
                    brace_count += 1;
                }
                '}' => {
                    brace_count -= 1;
                    if in_body && brace_count == 0 {
                        body_end = Some(idx + 1);
                        break;
                    }
                }
                _ => {}
            }
        }

        let body_end = body_end.ok_or("failed to extract body from HSM response")?;
        let body_json = &value[body_start..body_end];

        // Parse the full response to get signature
        let hsm_response: HsmResponse = serde_json::from_str(&value)
            .map_err(|e| format!("failed to parse HSM response: {}", e))?;

        // Verify HSM identity
        if hsm_response.body.hsm_identity != HSM_PUBLIC_KEY {
            return Err("invalid HSM identity".to_string());
        }

        // Verify the signature over the raw body JSON
        let verifier = Secp256r1VerifierStatic;
        verifier.verify(body_json, &hsm_response.signature, HSM_PUBLIC_KEY).await?;

        // Validate purpose
        if hsm_response.body.payload.purpose != "access" {
            return Err(format!("invalid purpose: expected access, got {}", hsm_response.body.payload.purpose));
        }

        // Check expiration
        let expiration = chrono::DateTime::parse_from_rfc3339(&hsm_response.body.payload.expiration)
            .map_err(|e| format!("failed to parse expiration: {}", e))?;
        if expiration <= chrono::Utc::now() {
            return Err("key expired".to_string());
        }

        // Return the public key from the payload
        Ok(Box::new(PublicKeyWrapper {
            public_key: hsm_response.body.payload.public_key
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
