# Fusion Video Engine

This folder contains the native editing engine foundation for Fusion Video.

Planned structure:

- `rust_core/`
  - orchestration layer
  - project state
  - timeline execution
  - engine API exposed over FFI
- platform adapters
  - iOS media/render integration
  - Android media/render integration

This layer is intentionally separate from Flutter UI code.
