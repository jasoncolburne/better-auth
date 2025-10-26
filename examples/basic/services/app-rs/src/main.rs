use axum::{
    extract::State,
    http::StatusCode,
    routing::{get, post},
    Router,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::HashMap;
use std::sync::Arc;
use tower_http::cors::CorsLayer;

use better_auth::api::server::{
    AccessVerifier, AccessVerifierAccessStore, AccessVerifierCrypto, AccessVerifierEncoding,
    AccessVerifierStore,
};
use better_auth::interfaces::{SigningKey, VerificationKey};
use better_auth::messages::{AccessToken, ServerResponse};
use better_auth::messages::{Serializable, Signable};

mod implementation;

use implementation::{
    Rfc3339Nano, RedisVerificationKeyStore, Secp256r1, Secp256r1Verifier, ServerTimeLockStore,
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
            eprintln!("Error handling /foo/bar: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                r#"{"error":"internal server error"}"#.to_string(),
            )
        }
    }
}

async fn handle_foo_bar(state: &AppState, message: String) -> Result<String, String> {
    // Verify the access request
    let (request, token, nonce): (RequestPayload, AccessToken<TokenAttributes>, String) =
        state.av.verify(&message).await?;

    // Check permissions
    if let Some(user_permissions) = token.attributes.permissions_by_role.get("user") {
        if !user_permissions.contains(&"read".to_string()) {
            return Err("unauthorized: missing read permission".to_string());
        }
    } else {
        return Err("unauthorized: no user permissions".to_string());
    }

    // Get server identity
    let server_identity = state.response_key.identity().await?;

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

    // Sign the response
    response.sign(state.response_key.as_ref()).await?;

    // Serialize to JSON
    response.to_json().await
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

    println!("Connecting to Redis at {}", redis_host);
    println!("Access keys DB: {}", redis_db_access_keys);
    println!("Response keys DB: {}", redis_db_response_keys);

    // Create Redis clients
    let access_redis_url = format!("redis://{}/{}", redis_host, redis_db_access_keys);
    let response_redis_url = format!("redis://{}/{}", redis_host, redis_db_response_keys);

    let access_client = redis::Client::open(access_redis_url.as_str())?;
    let response_client = redis::Client::open(response_redis_url.as_str())?;

    let access_conn = access_client
        .get_connection_manager()
        .await
        .map_err(|e| format!("Failed to connect to Redis (access): {}", e))?;
    let mut response_conn = response_client
        .get_connection()
        .map_err(|e| format!("Failed to connect to Redis (response): {}", e))?;

    println!("Connected to Redis");

    // Create crypto components
    let verifier = Secp256r1Verifier::new();

    // Create storage components
    let access_window = 30; // 30 seconds
    let access_nonce_store = ServerTimeLockStore::new(access_window);
    let access_key_store = RedisVerificationKeyStore::new(access_conn);

    // Create encoding components
    let timestamper = Rfc3339Nano::new();
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
