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

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LogEntry {
    id: String,
    prefix: String,
    previous: Option<String>,
    sequence_number: i32,
    created_at: String,
    taint_previous: Option<bool>,
    purpose: String,
    public_key: String,
    rotation_hash: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct SignedLogEntry {
    payload: LogEntry,
    signature: String,
}

struct ExpiringEntry {
    entry: LogEntry,
    expiration: Option<DateTime<Utc>>,
}

pub struct KeyVerifier {
    connection: Arc<Mutex<ConnectionManager>>,
    cache: Arc<Mutex<HashMap<String, ExpiringEntry>>>,
    verification_window_seconds: i64,
}

impl KeyVerifier {
    pub fn new(connection: ConnectionManager, server_lifetime_hours: i64, access_lifetime_minutes: i64) -> Self {
        Self {
            connection: Arc::new(Mutex::new(connection)),
            cache: Arc::new(Mutex::new(HashMap::new())),
            verification_window_seconds: server_lifetime_hours * 3600 + access_lifetime_minutes * 60,
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

        // Clear cache before repopulating
        let mut cache = self.cache.lock().await;
        cache.clear();
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
                .or_default()
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
            let mut last_created_at = DateTime::parse_from_rfc3339("1970-01-01T00:00:00Z")
                .unwrap()
                .with_timezone(&Utc);

            for (i, (record, _)) in records.iter().enumerate() {
                let payload = &record.payload;

                if payload.sequence_number != i as i32 {
                    return Err("bad sequence number".to_string());
                }

                // Validate timestamp ordering
                let created_at = DateTime::parse_from_rfc3339(&payload.created_at)
                    .map_err(|e| format!("Failed to parse created_at: {}", e))?
                    .with_timezone(&Utc);

                if created_at >= Utc::now() {
                    return Err("future timestamp".to_string());
                }

                if payload.sequence_number != 0 {
                    if &last_id != payload.previous.as_ref().ok_or("missing previous")? {
                        return Err("broken chain".to_string());
                    }

                    if created_at <= last_created_at {
                        return Err("non-increasing timestamp".to_string());
                    }

                    let hasher = Blake3Hasher::new();
                    let hash = hasher.sum(&payload.public_key);

                    if hash != last_rotation_hash {
                        return Err("bad commitment".to_string());
                    }
                }

                last_id = payload.id.clone();
                last_rotation_hash = payload.rotation_hash.clone();
                last_created_at = created_at;
            }
        }

        // Verify prefix exists
        let records = by_prefix.get(HSM_IDENTITY)
            .ok_or("hsm identity not found".to_string())?;

        // Cache entries within 12-hour window (iterate backwards)
        let mut cache = self.cache.lock().await;
        let mut tainted = false;
        let mut expiration: Option<DateTime<Utc>> = None;
        for (record, _) in records.iter().rev() {
            let payload = &record.payload;

            if !tainted {
                cache.insert(payload.id.clone(), ExpiringEntry {
                    entry: payload.clone(),
                    expiration,
                });
            }

            tainted = payload.taint_previous.unwrap_or(false);

            let created_at = DateTime::parse_from_rfc3339(&payload.created_at)
                .map_err(|e| format!("Failed to parse created_at: {}", e))?
                .with_timezone(&Utc);

            let exp = created_at + Duration::seconds(self.verification_window_seconds);
            expiration = Some(exp);

            if exp < Utc::now() {
                break;
            }
        }

        let cached_entry = cache.get(hsm_generation_id)
            .ok_or("can't find valid public key".to_string())?;

        self.verify_with_entry(cached_entry, signature, hsm_identity, message).await
    }

    async fn verify_with_entry(
        &self,
        cached_entry: &ExpiringEntry,
        signature: &str,
        hsm_identity: &str,
        message: &str,
    ) -> Result<(), String> {
        if cached_entry.entry.prefix != hsm_identity {
            return Err("incorrect identity (expected hsm.identity == prefix)".to_string());
        }

        if cached_entry.entry.purpose != "key-authorization" {
            return Err("incorrect purpose (expected key-authorization)".to_string());
        }

        if let Some(expiration) = cached_entry.expiration {
            if expiration < Utc::now() {
                return Err("expired key".to_string());
            }
        }

        // Verify message signature
        let verifier = Secp256r1Verifier::new();
        verifier.verify(message, signature, &cached_entry.entry.public_key).await
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
