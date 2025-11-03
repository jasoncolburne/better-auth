use axum::{
    extract::State,
    http::StatusCode,
    routing::{get, post},
    Router,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tower_http::cors::CorsLayer;

use better_auth::api::server::{
    AccessVerifier, AccessVerifierAccessStore, AccessVerifierCrypto, AccessVerifierEncoding,
    AccessVerifierStore,
};
use better_auth::error::BetterAuthError;
use better_auth::interfaces::{SigningKey, VerificationKey};
use better_auth::messages::{AccessToken, ServerResponse};
use better_auth::messages::{Serializable, Signable};

mod implementation;

// Custom error type for the application
#[derive(Debug)]
enum AppError {
    Auth(String),
    Redis(String),
    Permission(String),
    Serialization(String),
    Signing(String),
}

impl std::fmt::Display for AppError {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            AppError::Auth(e) => write!(f, "Authentication error: {}", e),
            AppError::Redis(e) => write!(f, "Redis error: {}", e),
            AppError::Permission(e) => write!(f, "Permission error: {}", e),
            AppError::Serialization(e) => write!(f, "Serialization error: {}", e),
            AppError::Signing(e) => write!(f, "Signing error: {}", e),
        }
    }
}

impl From<String> for AppError {
    fn from(s: String) -> Self {
        AppError::Auth(s)
    }
}

impl From<AppError> for BetterAuthError {
    fn from(err: AppError) -> BetterAuthError {
        match err {
            AppError::Auth(e) => BetterAuthError::new("APP001", format!("Auth: {}", e)),
            AppError::Redis(e) => BetterAuthError::new("APP002", format!("Redis: {}", e)),
            AppError::Permission(e) => BetterAuthError::new("APP003", format!("Permission: {}", e)),
            AppError::Serialization(e) => BetterAuthError::new("APP004", format!("Serialization: {}", e)),
            AppError::Signing(e) => BetterAuthError::new("APP005", format!("Signing: {}", e)),
        }
    }
}

use implementation::{
    Rfc3339, RedisVerificationKeyStore, Secp256r1, Secp256r1Verifier, ServerTimeLockStore,
    TokenEncoder,
};

#[derive(Clone, Serialize, Deserialize)]
struct TokenAttributes {
    #[serde(rename = "permissionsByRole")]
    permissions_by_role: HashMap<String, Vec<String>>,
}

#[derive(Clone, Serialize, Deserialize)]
struct RequestPayload {
    foo: String,
    bar: String,
}

#[derive(Clone, Serialize, Deserialize)]
struct ResponsePayload {
    #[serde(rename = "wasFoo")]
    was_foo: String,
    #[serde(rename = "wasBar")]
    was_bar: String,
    #[serde(rename = "serverName")]
    server_name: String,
}

#[derive(Clone, Serialize, Deserialize)]
struct HealthResponse {
    status: String,
}

#[derive(Clone)]
struct AppState {
    av: Arc<AccessVerifier>,
    response_key: Arc<Secp256r1>,
    revoked_devices_client: redis::aio::ConnectionManager,
}

async fn health() -> (StatusCode, axum::Json<HealthResponse>) {
    (
        StatusCode::OK,
        axum::Json(HealthResponse {
            status: "healthy".to_string(),
        }),
    )
}

async fn foo_bar(State(state): State<AppState>, body: String) -> (StatusCode, String) {
    match handle_foo_bar(&state, body).await {
        Ok(response) => (StatusCode::OK, response),
        Err(e) => {
            // Application boundary: convert AppError to string for HTTP response
            eprintln!("Error handling /foo/bar: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!(r#"{{"error":"{}"}}"#, e),
            )
        }
    }
}

async fn handle_foo_bar(state: &AppState, message: String) -> Result<String, AppError> {
    // Verify the access request
    let (request, token, nonce): (RequestPayload, AccessToken<TokenAttributes>, String) =
        state.av.verify(&message).await.map_err(|e| AppError::Auth(e.to_string()))?;

    // Check if device is revoked
    use redis::AsyncCommands;
    let mut conn = state.revoked_devices_client.clone();
    let is_revoked: bool = conn
        .exists(&token.device)
        .await
        .map_err(|e| AppError::Redis(format!("Failed to check revoked devices: {}", e)))?;

    if is_revoked {
        return Err(AppError::Permission("device revoked".to_string()));
    }

    // Check permissions
    if let Some(user_permissions) = token.attributes.permissions_by_role.get("user") {
        if !user_permissions.contains(&"read".to_string()) {
            return Err(AppError::Permission("unauthorized: missing read permission".to_string()));
        }
    } else {
        return Err(AppError::Permission("unauthorized: no user permissions".to_string()));
    }

    // Get server identity
    let server_identity = state.response_key.identity().await.map_err(AppError::Auth)?;

    // Create response
    let mut response: ServerResponse<ResponsePayload> = ServerResponse::new(
        ResponsePayload {
            was_foo: request.foo,
            was_bar: request.bar,
            server_name: "rust".to_string(),
        },
        server_identity,
        nonce,
    );

    // Sign the response - no conversion needed! Library handles it via Into<BetterAuthError>
    response.sign(state.response_key.as_ref()).await.map_err(|e| AppError::Signing(e.to_string()))?;

    // Serialize to JSON - no conversion needed! Library handles it via Into<BetterAuthError>
    response.to_json().await.map_err(|e| AppError::Serialization(e.to_string()))
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("Starting Rust application server...");

    // Read environment variables
    let redis_host = std::env::var("REDIS_HOST").unwrap_or_else(|_| "redis:6379".to_string());
    let redis_db_access_keys: u32 = std::env::var("REDIS_DB_ACCESS_KEYS")
        .unwrap_or_else(|_| "0".to_string())
        .parse()
        .unwrap_or(0);
    let redis_db_response_keys: u32 = std::env::var("REDIS_DB_RESPONSE_KEYS")
        .unwrap_or_else(|_| "1".to_string())
        .parse()
        .unwrap_or(1);
    let redis_db_revoked_devices: u32 = std::env::var("REDIS_DB_REVOKED_DEVICES")
        .unwrap_or_else(|_| "3".to_string())
        .parse()
        .unwrap_or(3);
    let redis_db_hsm_keys: u32 = std::env::var("REDIS_DB_HSM_KEYS")
        .unwrap_or_else(|_| "4".to_string())
        .parse()
        .unwrap_or(4);

    println!("Connecting to Redis at {}", redis_host);
    println!("Access keys DB: {}", redis_db_access_keys);
    println!("Response keys DB: {}", redis_db_response_keys);
    println!("Revoked devices DB: {}", redis_db_revoked_devices);
    println!("HSM keys DB: {}", redis_db_hsm_keys);

    // Create Redis clients
    let access_redis_url = format!("redis://{}/{}", redis_host, redis_db_access_keys);
    let response_redis_url = format!("redis://{}/{}", redis_host, redis_db_response_keys);
    let revoked_devices_redis_url = format!("redis://{}/{}", redis_host, redis_db_revoked_devices);
    let hsm_redis_url = format!("redis://{}/{}", redis_host, redis_db_hsm_keys);

    let access_client = redis::Client::open(access_redis_url.as_str())?;
    let response_client = redis::Client::open(response_redis_url.as_str())?;
    let revoked_devices_client = redis::Client::open(revoked_devices_redis_url.as_str())?;
    let hsm_client = redis::Client::open(hsm_redis_url.as_str())?;

    let access_conn = access_client
        .get_connection_manager()
        .await
        .map_err(|e| format!("Failed to connect to Redis (access): {}", e))?;
    let revoked_devices_conn = revoked_devices_client
        .get_connection_manager()
        .await
        .map_err(|e| format!("Failed to connect to Redis (revoked devices): {}", e))?;
    let hsm_conn = hsm_client
        .get_connection_manager()
        .await
        .map_err(|e| format!("Failed to connect to Redis (HSM keys): {}", e))?;
    let mut response_conn = response_client
        .get_connection()
        .map_err(|e| format!("Failed to connect to Redis (response): {}", e))?;

    println!("Connected to Redis");

    // Create crypto components
    let verifier = Secp256r1Verifier::new();

    // Create storage components
    let access_window = 30; // 30 seconds
    let server_lifetime_hours = 12;
    let access_lifetime_minutes = 15;
    let access_nonce_store = ServerTimeLockStore::new(access_window);
    let access_key_store = RedisVerificationKeyStore::new(access_conn, hsm_conn, server_lifetime_hours, access_lifetime_minutes);

    // Create encoding components
    let timestamper = Rfc3339::new();
    let token_encoder = TokenEncoder::new();

    // Generate and register response key
    let mut response_key = Secp256r1::new();
    response_key.generate()?;
    let response_public_key = response_key.public().await?;

    // Sign response key with HSM
    let hsm_host = std::env::var("HSM_HOST").unwrap_or_else(|_| "hsm".to_string());
    let hsm_port = std::env::var("HSM_PORT").unwrap_or_else(|_| "11111".to_string());
    let hsm_url = format!("http://{}:{}", hsm_host, hsm_port);

    let ttl_seconds = 12 * 60 * 60 + 60; // 43260 seconds
    let response_expiration = chrono::Utc::now() + chrono::Duration::seconds(ttl_seconds as i64);
    let expiration_str = response_expiration.to_rfc3339_opts(chrono::SecondsFormat::Nanos, true);

    // Build JSON manually for deterministic ordering: purpose, publicKey, expiration
    let response_payload_json = format!(
        r#"{{"purpose":"response","publicKey":"{}","expiration":"{}"}}"#,
        response_public_key, expiration_str
    );

    let hsm_request_json = format!(r#"{{"payload":{}}}"#, response_payload_json);

    let client = reqwest::Client::new();
    let authorization = match client
        .post(format!("{}/sign", hsm_url))
        .header("Content-Type", "application/json")
        .body(hsm_request_json)
        .send()
        .await
    {
        Ok(resp) if resp.status().is_success() => {
            match resp.text().await {
                Ok(text) => {
                    let trimmed = text.trim_end().to_string();
                    println!("Response key HSM authorization: {}", trimmed);
                    Some(trimmed)
                }
                Err(e) => {
                    println!("Warning: Failed to read HSM response: {}", e);
                    None
                }
            }
        }
        Ok(resp) => {
            println!(
                "Warning: Failed to sign response key with HSM: {}",
                resp.status()
            );
            None
        }
        Err(e) => {
            println!("Warning: Failed to contact HSM: {}", e);
            None
        }
    };

    // Store the full HSM authorization in Redis DB 1 with 12 hour 1 minute TTL
    if let Some(auth) = authorization {
        redis::cmd("SET")
            .arg(&response_public_key)
            .arg(&auth)
            .arg("EX")
            .arg(ttl_seconds)
            .query::<()>(&mut response_conn)
            .map_err(|e| format!("Failed to register response key: {}", e))?;

        println!(
            "Registered app response key in Redis DB {} (TTL: 12 hours): {}...",
            redis_db_response_keys,
            &response_public_key[..20]
        );
    } else {
        println!("Warning: No HSM authorization to store in Redis");
    }

    // Drop response connection (we don't need it anymore)
    drop(response_conn);

    // Create AccessVerifier
    let av = AccessVerifier {
        crypto: AccessVerifierCrypto {
            verifier: Box::new(verifier),
        },
        encoding: AccessVerifierEncoding {
            token_encoder: Box::new(token_encoder),
            timestamper: Box::new(timestamper),
        },
        store: AccessVerifierStore {
            access: AccessVerifierAccessStore {
                nonce: Box::new(access_nonce_store),
                key: Box::new(access_key_store),
            },
        },
    };

    println!("AccessVerifier initialized");

    let state = AppState {
        av: Arc::new(av),
        response_key: Arc::new(response_key),
        revoked_devices_client: revoked_devices_conn,
    };

    println!("Application server initialized");

    // Build the router
    let app = Router::new()
        .route("/health", get(health))
        .route("/foo/bar", post(foo_bar))
        .layer(CorsLayer::permissive())
        .with_state(state);

    // Start the server
    let listener = tokio::net::TcpListener::bind("0.0.0.0:80").await?;
    println!("Application server running on port 80");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    println!("Server shut down gracefully");

    Ok(())
}

async fn shutdown_signal() {
    use tokio::signal;

    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {
            println!("Received Ctrl+C, shutting down...");
        },
        _ = terminate => {
            println!("Received SIGTERM, shutting down...");
        },
    }
}
