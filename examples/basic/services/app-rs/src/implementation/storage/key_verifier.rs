use async_trait::async_trait;
use chrono::{DateTime, Duration, Utc};
use redis::aio::ConnectionManager;
use redis::{AsyncCommands, RedisError};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

use better_auth::interfaces::Verifier;
use super::super::crypto::{Blake3Hasher, Secp256r1Verifier};
use super::utils::get_sub_json;

const HSM_IDENTITY: &str = "BETTER_AUTH_HSM_IDENTITY_PLACEHOLDER";
const TWELVE_HOURS_FIFTEEN_MINUTES_SECONDS: i64 = 12 * 3600 + 15 * 60;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LogEntry {
    id: String,
    prefix: String,
    previous: Option<String>,
    sequence_number: i32,
    created_at: String,
    purpose: String,
    public_key: String,
    rotation_hash: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct SignedLogEntry {
    payload: LogEntry,
    signature: String,
}

pub struct KeyVerifier {
    connection: Arc<Mutex<ConnectionManager>>,
    cache: Arc<Mutex<HashMap<String, LogEntry>>>,
}

impl KeyVerifier {
    pub fn new(connection: ConnectionManager) -> Self {
        Self {
            connection: Arc::new(Mutex::new(connection)),
            cache: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub async fn verify(
        &self,
        signature: &str,
        hsm_identity: &str,
        hsm_generation_id: &str,
        message: &str,
    ) -> Result<(), String> {
        let cache = self.cache.lock().await;

        if let Some(cached_entry) = cache.get(hsm_generation_id) {
            return self.verify_with_entry(cached_entry, signature, hsm_identity, message).await;
        }

        drop(cache);

        // Fetch all HSM keys from Redis
        let mut conn = self.connection.lock().await;
        let keys: Vec<String> = conn.keys("*").await
            .map_err(|e| format!("Redis keys error: {}", e))?;

        if keys.is_empty() {
            return Err("No HSM keys found in Redis".to_string());
        }

        let values: Vec<Option<String>> = conn.mget(&keys).await
            .map_err(|e| format!("Redis mget error: {}", e))?;

        drop(conn);

        // Group by prefix
        let mut by_prefix: HashMap<String, Vec<(SignedLogEntry, String)>> = HashMap::new();

        for value in values.into_iter().flatten() {
            let payload_json = get_sub_json(&value, "payload")?;
            let record: SignedLogEntry = serde_json::from_str(&value)
                .map_err(|e| format!("Failed to parse HSM record: {}", e))?;

            by_prefix.entry(record.payload.prefix.clone())
                .or_insert_with(Vec::new)
                .push((record, payload_json));
        }

        // Sort by sequence number
        for records in by_prefix.values_mut() {
            records.sort_by_key(|(r, _)| r.payload.sequence_number);
        }

        // Verify data & signatures
        for records in by_prefix.values() {
            for (record, payload_json) in records {
                let payload = &record.payload;

                if payload.sequence_number == 0 {
                    Self::verify_prefix_and_data(payload_json, payload).await?;
                } else {
                    Self::verify_address_and_data(payload_json, payload).await?;
                }

                // Verify signature over payload using the extracted JSON string
                let verifier = Secp256r1Verifier::new();
                verifier.verify(payload_json, &record.signature, &payload.public_key).await?;
            }
        }

        // Verify chains
        for records in by_prefix.values() {
            let mut last_id = String::new();
            let mut last_rotation_hash = String::new();

            for (i, (record, _)) in records.iter().enumerate() {
                let payload = &record.payload;

                if payload.sequence_number != i as i32 {
                    return Err("bad sequence number".to_string());
                }

                if payload.sequence_number != 0 {
                    if &last_id != payload.previous.as_ref().ok_or("missing previous")? {
                        return Err("broken chain".to_string());
                    }

                    let hasher = Blake3Hasher::new();
                    let hash = hasher.sum(&payload.public_key);

                    if hash != last_rotation_hash {
                        return Err("bad commitment".to_string());
                    }
                }

                last_id = payload.id.clone();
                last_rotation_hash = payload.rotation_hash.clone();
            }
        }

        // Verify prefix exists
        let records = by_prefix.get(HSM_IDENTITY)
            .ok_or("hsm identity not found".to_string())?;

        // Cache entries within 12-hour window (iterate backwards)
        let mut cache = self.cache.lock().await;
        for (record, _) in records.iter().rev() {
            let payload = &record.payload;
            cache.insert(payload.id.clone(), payload.clone());

            let created_at = DateTime::parse_from_rfc3339(&payload.created_at)
                .map_err(|e| format!("Failed to parse created_at: {}", e))?;

            if created_at.with_timezone(&Utc) + Duration::seconds(TWELVE_HOURS_FIFTEEN_MINUTES_SECONDS) < Utc::now() {
                break;
            }
        }

        let cached_entry = cache.get(hsm_generation_id)
            .ok_or("can't find valid public key".to_string())?;

        self.verify_with_entry(cached_entry, signature, hsm_identity, message).await
    }

    async fn verify_with_entry(
        &self,
        cached_entry: &LogEntry,
        signature: &str,
        hsm_identity: &str,
        message: &str,
    ) -> Result<(), String> {
        if cached_entry.prefix != hsm_identity {
            return Err("incorrect identity (expected hsm.identity == prefix)".to_string());
        }

        if cached_entry.purpose != "key-authorization" {
            return Err("incorrect purpose (expected key-authorization)".to_string());
        }

        // Verify message signature
        let verifier = Secp256r1Verifier::new();
        verifier.verify(message, signature, &cached_entry.public_key).await
    }

    async fn verify_prefix_and_data(payload_json: &str, payload: &LogEntry) -> Result<(), String> {
        if payload.id != payload.prefix {
            return Err("prefix must equal id for sequence 0".to_string());
        }

        Self::verify_address_and_data(payload_json, payload).await
    }

    async fn verify_address_and_data(payload_json: &str, payload: &LogEntry) -> Result<(), String> {
        let modified_payload = payload_json.replace(&payload.id, "############################################");

        let hasher = Blake3Hasher::new();
        let hash = hasher.sum(&modified_payload);

        if hash != payload.id {
            return Err("id does not match hash of payload".to_string());
        }

        Ok(())
    }
}
