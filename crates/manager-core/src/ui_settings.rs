use crate::{ErrorCode, Language, ManagerError};
use serde::{
    de::{self, MapAccess, Visitor},
    Deserialize,
};
use serde_json::value::RawValue;
use std::{
    collections::BTreeMap,
    fs::{self, File, OpenOptions},
    io::{self, Read, Write},
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
};

static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);
const MAX_SETTINGS_BYTES: u64 = 64 * 1024;
type SettingsObject = BTreeMap<String, Box<RawValue>>;

// Retain unknown JSON tokens verbatim: decoding them into f64/Value would round
// large integers and high-precision decimals when another UI adds a setting.
struct UniqueObject(SettingsObject);
impl<'de> Deserialize<'de> for UniqueObject {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct ObjectVisitor;
        impl<'de> Visitor<'de> for ObjectVisitor {
            type Value = UniqueObject;
            fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
                f.write_str("a JSON object without duplicate properties")
            }
            fn visit_map<M: MapAccess<'de>>(self, mut access: M) -> Result<Self::Value, M::Error> {
                let mut map = BTreeMap::new();
                while let Some((key, value)) = access.next_entry::<String, Box<RawValue>>()? {
                    if map.insert(key, value).is_some() {
                        return Err(de::Error::custom("duplicate JSON property"));
                    }
                }
                Ok(UniqueObject(map))
            }
        }
        deserializer.deserialize_map(ObjectVisitor)
    }
}

fn invalid_settings() -> ManagerError {
    ManagerError::new(ErrorCode::SettingsInvalid, "")
}

fn validate_value(value: &RawValue, depth: usize) -> Result<(), ManagerError> {
    match value.get().as_bytes().first() {
        Some(b'{') => {
            if depth >= 64 {
                return Err(invalid_settings());
            }
            let object: UniqueObject =
                serde_json::from_str(value.get()).map_err(|_| invalid_settings())?;
            for child in object.0.values() {
                validate_value(child, depth + 1)?;
            }
        }
        Some(b'[') => {
            if depth >= 64 {
                return Err(invalid_settings());
            }
            let array: Vec<Box<RawValue>> =
                serde_json::from_str(value.get()).map_err(|_| invalid_settings())?;
            for child in array {
                validate_value(&child, depth + 1)?;
            }
        }
        _ => {}
    }
    Ok(())
}

/// Shared with WinUI; preferences never enter profiles.toml or the Runner contract.
pub struct UiSettingsStore {
    path: PathBuf,
}

impl UiSettingsStore {
    pub fn new(data_root: impl Into<PathBuf>) -> Self {
        Self {
            path: data_root.into().join("ui-settings.json"),
        }
    }

    fn read_bytes(&self) -> Result<Option<Vec<u8>>, ManagerError> {
        let file = match File::open(&self.path) {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(ManagerError::new(ErrorCode::SettingsRead, error)),
        };
        let mut bytes = Vec::new();
        file.take(MAX_SETTINGS_BYTES + 1)
            .read_to_end(&mut bytes)
            .map_err(|error| ManagerError::new(ErrorCode::SettingsRead, error))?;
        if bytes.len() as u64 > MAX_SETTINGS_BYTES {
            return Err(ManagerError::new(ErrorCode::SettingsTooLarge, ""));
        }
        Ok(Some(bytes))
    }

    fn parse_object(bytes: Option<&[u8]>) -> Result<SettingsObject, ManagerError> {
        let Some(bytes) = bytes else {
            return Ok(BTreeMap::new());
        };
        // Windows tools may write a UTF-8 BOM; accept it in both UI implementations.
        let bytes = bytes.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(bytes);
        let raw: Box<RawValue> = serde_json::from_slice(bytes).map_err(|_| invalid_settings())?;
        validate_value(&raw, 0)?;
        serde_json::from_str::<UniqueObject>(raw.get())
            .map(|object| object.0)
            .map_err(|_| invalid_settings())
    }

    pub fn load_language(&self) -> Result<Language, ManagerError> {
        Ok(Self::parse_object(self.read_bytes()?.as_deref())?
            .get("language")
            .and_then(|value| serde_json::from_str::<String>(value.get()).ok())
            .map(|value| Language::parse(&value))
            .unwrap_or_default())
    }

    pub fn save_language(&self, language: Language) -> Result<(), ManagerError> {
        let parent = self.path.parent().expect("UI settings have a data root");
        fs::create_dir_all(parent)
            .map_err(|error| ManagerError::new(ErrorCode::SettingsWrite, error))?;
        // WinUI holds this same lease with FileShare.None. It remains an empty file.
        let mut lock_options = OpenOptions::new();
        lock_options
            .read(true)
            .write(true)
            .create(true)
            .truncate(false);
        #[cfg(windows)]
        {
            use std::os::windows::fs::OpenOptionsExt;
            lock_options.share_mode(0);
        }
        let _lease = lock_options
            .open(parent.join("ui-settings.json.lock"))
            .map_err(|error| ManagerError::new(ErrorCode::SettingsWrite, error))?;
        let before = self.read_bytes()?;
        let mut object = Self::parse_object(before.as_deref())?;
        object.insert(
            "language".into(),
            RawValue::from_string(format!("\"{}\"", language.tag()))
                .expect("canonical language tags are valid JSON strings"),
        );
        let bytes = serde_json::to_vec_pretty(&object)
            .map_err(|error| ManagerError::new(ErrorCode::SettingsWrite, error))?;
        if bytes.len() as u64 + 1 > MAX_SETTINGS_BYTES {
            return Err(ManagerError::new(ErrorCode::SettingsTooLarge, ""));
        }
        let temporary = parent.join(format!(
            ".ui-settings.json.tmp-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        let result = (|| -> io::Result<()> {
            let mut file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temporary)?;
            file.write_all(&bytes)?;
            file.write_all(b"\n")?;
            file.sync_all()?;
            drop(file);
            let current = self.read_bytes().map_err(io::Error::other)?;
            if current != before {
                return Err(io::Error::other("UI settings changed during the write"));
            }
            crate::runner::replace_file(&temporary, &self.path)
        })();
        if result.is_err() {
            let _ = fs::remove_file(&temporary);
        }
        result.map_err(|error| ManagerError::new(ErrorCode::SettingsWrite, error))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Fixture(PathBuf);
    impl Fixture {
        fn new() -> Self {
            let root = std::env::temp_dir().join(format!(
                "steamwrapper-language-{}-{}",
                std::process::id(),
                NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&root).unwrap();
            Self(root)
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn defaults_to_english_and_normalizes_both_ui_language_aliases() {
        let root = Fixture::new();
        let store = UiSettingsStore::new(&root.0);
        assert_eq!(store.load_language().unwrap(), Language::English);
        assert!(!store.path.exists());
        for (value, expected) in [
            (" en ", Language::English),
            ("EN-us", Language::English),
            (" zh-Hans ", Language::SimplifiedChinese),
            ("ZH-cn", Language::SimplifiedChinese),
            ("fr-FR", Language::English),
        ] {
            fs::write(&store.path, format!(r#"{{"language":"{value}"}}"#)).unwrap();
            assert_eq!(store.load_language().unwrap(), expected);
        }
        fs::write(&store.path, b"\xef\xbb\xbf{\"language\":\"zh-CN\"}").unwrap();
        assert_eq!(store.load_language().unwrap(), Language::SimplifiedChinese);
        for value in ["null", "5", "false", "{}"] {
            fs::write(&store.path, format!(r#"{{"language":{value}}}"#)).unwrap();
            assert_eq!(store.load_language().unwrap(), Language::English);
        }
    }

    #[test]
    fn preserves_unknown_fields_and_profiles_across_language_changes() {
        let root = Fixture::new();
        let store = UiSettingsStore::new(&root.0);
        fs::write(&store.path, br#"{"theme":{"future":true},"language":"en"}"#).unwrap();
        let profile = root.0.join("profiles.toml");
        fs::write(&profile, b"user data").unwrap();
        store.save_language(Language::SimplifiedChinese).unwrap();
        assert_eq!(
            UiSettingsStore::new(&root.0).load_language().unwrap(),
            Language::SimplifiedChinese
        );
        let json: serde_json::Value =
            serde_json::from_slice(&fs::read(&store.path).unwrap()).unwrap();
        assert_eq!(json["theme"]["future"], true);
        assert_eq!(json["language"], "zh-CN");
        assert_eq!(fs::read(profile).unwrap(), b"user data");
        store.save_language(Language::English).unwrap();
        assert_eq!(store.load_language().unwrap(), Language::English);
    }

    #[test]
    fn invalid_or_unreadable_settings_are_reported_and_never_overwritten() {
        let root = Fixture::new();
        let store = UiSettingsStore::new(&root.0);
        for bytes in [b"{invalid".as_slice(), b"[]", b"null"] {
            fs::write(&store.path, bytes).unwrap();
            assert_eq!(
                store.load_language().unwrap_err().code,
                ErrorCode::SettingsInvalid
            );
            assert!(store.save_language(Language::SimplifiedChinese).is_err());
            assert_eq!(fs::read(&store.path).unwrap(), bytes);
        }
        fs::remove_file(&store.path).unwrap();
        fs::create_dir(&store.path).unwrap();
        assert_eq!(
            store.load_language().unwrap_err().code,
            ErrorCode::SettingsRead
        );
        assert!(store.save_language(Language::English).is_err());
        assert!(store.path.is_dir());
    }

    #[test]
    fn rejects_duplicate_fields_and_oversized_documents_without_rewriting() {
        let root = Fixture::new();
        let store = UiSettingsStore::new(&root.0);
        for bytes in [
            br#"{"language":"en-US","language":"zh-CN"}"#.to_vec(),
            br#"{"future":{"x":1,"x":2}}"#.to_vec(),
            vec![b' '; 65537],
        ] {
            fs::write(&store.path, &bytes).unwrap();
            assert_eq!(
                store.load_language().unwrap_err().code,
                if bytes.len() > MAX_SETTINGS_BYTES as usize {
                    ErrorCode::SettingsTooLarge
                } else {
                    ErrorCode::SettingsInvalid
                }
            );
            assert!(store.save_language(Language::SimplifiedChinese).is_err());
            assert_eq!(fs::read(&store.path).unwrap(), bytes);
        }
    }

    #[cfg(windows)]
    #[test]
    fn respects_the_shared_winui_exclusive_lease() {
        use std::os::windows::fs::OpenOptionsExt;
        let root = Fixture::new();
        let store = UiSettingsStore::new(&root.0);
        store.save_language(Language::English).unwrap();
        let before = fs::read(&store.path).unwrap();
        let lease = OpenOptions::new()
            .read(true)
            .write(true)
            .share_mode(0)
            .open(root.0.join("ui-settings.json.lock"))
            .unwrap();
        assert_eq!(
            store
                .save_language(Language::SimplifiedChinese)
                .unwrap_err()
                .code,
            ErrorCode::SettingsWrite
        );
        assert_eq!(fs::read(&store.path).unwrap(), before);
        drop(lease);
        store.save_language(Language::SimplifiedChinese).unwrap();
        assert_eq!(store.load_language().unwrap(), Language::SimplifiedChinese);
    }

    #[test]
    fn preserves_unknown_numeric_tokens_without_rounding() {
        let root = Fixture::new();
        let store = UiSettingsStore::new(&root.0);
        let numbers = ["18446744073709551617", "0.123456789012345678901", "1e400"];
        for number in numbers {
            let source = format!(r#"{{"language":"en-US","future":{{"number":{number}}}}}"#);
            fs::write(&store.path, &source).unwrap();
            store.save_language(Language::SimplifiedChinese).unwrap();
            let after = fs::read_to_string(&store.path).unwrap();
            assert!(
                after.contains(number),
                "unknown number was changed: {after}"
            );
        }
    }

    #[test]
    fn matches_the_winui_limit_of_64_json_container_levels() {
        let root = Fixture::new();
        let store = UiSettingsStore::new(&root.0);
        for (depth, valid) in [(64, true), (65, false)] {
            let source = format!(
                "{{\"future\":{}0{}}}",
                "[".repeat(depth - 1),
                "]".repeat(depth - 1)
            );
            fs::write(&store.path, &source).unwrap();
            assert_eq!(store.load_language().is_ok(), valid, "depth {depth}");
            assert_eq!(
                store.save_language(Language::SimplifiedChinese).is_ok(),
                valid,
                "depth {depth}"
            );
            if !valid {
                assert_eq!(fs::read_to_string(&store.path).unwrap(), source);
            }
        }
    }
}
