//! Fusion Video engine core scaffold.
//!
//! This crate is intentionally minimal in phase 1.
//! The first goal is to define stable module boundaries before playback,
//! decoding, or rendering logic is implemented.

pub mod api;
pub mod audio_engine;
pub mod export_engine;
pub mod ffi;
pub mod preview_engine;
pub mod project;
pub mod project_core;
pub mod render_graph;
pub mod timeline;
pub mod timeline_engine;

pub use api::EngineHandle;
