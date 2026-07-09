//! Linux / SteamOS runtime strategy.
//!
//! Planned implementation:
//! - preserve the Steam-expanded `%command%` environment as much as possible;
//! - support native Linux targets first;
//! - add Proton-aware wrapping after the Windows workflow is stable;
//! - use process group/session waiting for SteamOS-friendly runtime behavior.
