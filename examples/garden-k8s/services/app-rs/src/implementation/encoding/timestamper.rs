use better_auth::interfaces::Timestamper as TimestamperTrait;
use std::time::{Duration, SystemTime};

pub struct Rfc3339;

impl Default for Rfc3339 {
    fn default() -> Self {
        Self::new()
    }
}

impl Rfc3339 {
    pub fn new() -> Self {
        Self
    }
}

impl TimestamperTrait for Rfc3339 {
    fn format(&self, when: SystemTime) -> String {
        use chrono::{DateTime, Utc};

        let datetime: DateTime<Utc> = when.into();
        // RFC3339 with milliseconds (3 digits after decimal)
        datetime.to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
    }

    fn parse(&self, when: &str) -> Result<SystemTime, String> {
        use chrono::DateTime;

        DateTime::parse_from_rfc3339(when)
            .map(|dt| dt.into())
            .map_err(|e| format!("Failed to parse timestamp: {}", e))
    }

    fn now(&self) -> SystemTime {
        SystemTime::now()
    }

    fn add_minutes(&self, time: SystemTime, minutes: u32) -> SystemTime {
        time + Duration::from_secs((minutes as u64) * 60)
    }

    fn add_hours(&self, time: SystemTime, hours: u32) -> SystemTime {
        time + Duration::from_secs((hours as u64) * 60 * 60)
    }

    fn add_seconds(&self, time: SystemTime, seconds: u64) -> SystemTime {
        time + Duration::from_secs(seconds)
    }

    fn compare(&self, a: SystemTime, b: SystemTime) -> std::cmp::Ordering {
        a.cmp(&b)
    }
}
