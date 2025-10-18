use async_trait::async_trait;
use better_auth::interfaces::ServerTimeLockStore as ServerTimeLockStoreTrait;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::SystemTime;
use tokio::sync::Mutex;

#[derive(Clone)]
pub struct ServerTimeLockStore {
    nonces: Arc<Mutex<HashMap<String, SystemTime>>>,
    lifetime_in_seconds: u64,
}

impl ServerTimeLockStore {
    pub fn new(lifetime_in_seconds: u64) -> Self {
        Self {
            nonces: Arc::new(Mutex::new(HashMap::new())),
            lifetime_in_seconds,
        }
    }
}

#[async_trait]
impl ServerTimeLockStoreTrait for ServerTimeLockStore {
    fn lifetime_in_seconds(&self) -> u64 {
        self.lifetime_in_seconds
    }

    async fn reserve(&self, value: String) -> Result<(), String> {
        use std::time::Duration;

        let mut nonces = self.nonces.lock().await;

        if let Some(valid_at) = nonces.get(&value) {
            let now = SystemTime::now();
            if now < *valid_at {
                return Err("value reserved too recently".to_string());
            }
        }

        let new_valid_at = SystemTime::now() + Duration::from_secs(self.lifetime_in_seconds);
        nonces.insert(value, new_valid_at);

        Ok(())
    }
}
