use crate::Profile;
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("failed to read config: {0}")]
    Read(#[from] std::io::Error),
    #[error("failed to parse TOML config: {0}")]
    Parse(#[from] toml::de::Error),
    #[error("failed to serialize TOML config: {0}")]
    Serialize(#[from] toml::ser::Error),
    #[error("profile not found for appid: {0}")]
    ProfileNotFound(String),
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SteamWrapperConfig {
    pub version: u32,
    #[serde(default)]
    pub profiles: BTreeMap<String, Profile>,
}

impl Default for SteamWrapperConfig {
    fn default() -> Self {
        Self {
            version: 2,
            profiles: BTreeMap::new(),
        }
    }
}

impl SteamWrapperConfig {
    pub fn load(path: impl AsRef<Path>) -> Result<Self, ConfigError> {
        let text = fs::read_to_string(path)?;
        Ok(toml::from_str(&text)?)
    }

    pub fn save(&self, path: impl AsRef<Path>) -> Result<(), ConfigError> {
        let text = toml::to_string_pretty(self)?;
        fs::write(path, text)?;
        Ok(())
    }

    pub fn find_profile_by_appid(&self, appid: &str) -> Option<(&str, &Profile)> {
        self.profiles
            .iter()
            .find(|(key, profile)| key.as_str() == appid || profile.app_id.as_deref() == Some(appid))
            .map(|(key, profile)| (key.as_str(), profile))
    }

    pub fn require_profile_by_appid(&self, appid: &str) -> Result<(&str, &Profile), ConfigError> {
        self.find_profile_by_appid(appid)
            .ok_or_else(|| ConfigError::ProfileNotFound(appid.to_string()))
    }
}
