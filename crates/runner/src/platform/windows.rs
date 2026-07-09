//! Windows runtime strategy.
//!
//! Planned implementation:
//! - keep the runner as a GUI-subsystem/headless binary;
//! - launch the configured target with the requested working directory and args;
//! - use Windows Job Object for the default `job` wait mode;
//! - fall back to root-process or process-name wait modes for special launchers.
