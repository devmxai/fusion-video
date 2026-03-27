//! Fusion Video engine core scaffold.
//!
//! This crate is intentionally minimal in phase 1.
//! The first goal is to define stable module boundaries before playback,
//! decoding, or rendering logic is implemented.

pub mod api;
pub mod project;
pub mod timeline;

pub use api::EngineHandle;
