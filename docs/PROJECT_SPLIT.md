# Fusion Video Project Split

This document defines the practical split we should keep while debugging the
current editor issues.

## Layer Map

### `lib/features/editor/presentation`

Owns:

- screen layout
- user gestures
- timeline widgets
- preview shell widgets
- bottom sheets and toolbars

Should not own:

- scene mapping rules
- duration normalization rules
- export request shaping
- media metadata probing policy

### `lib/features/editor/application`

Owns:

- scene projection from engine snapshots into preview/export payloads
- media metadata normalization before timeline insertion
- runtime diagnostics and warning generation
- editor-level orchestration helpers that are still Flutter-side

This layer exists specifically to stop `MobileEditorScreen` from becoming the
hidden engine coordinator.

### `lib/core`

Owns stable contracts and bridges:

- `core/engine`: Flutter <-> Rust engine boundary
- `core/preview`: Flutter <-> native preview boundary
- `core/export`: Flutter <-> native export boundary
- `core/media`: local metadata probing

### `engine/rust_core`

Owns canonical timeline and transport state:

- clip insertion
- split / trim / duplicate / delete
- project duration recomputation
- composition node snapshots
- audio node snapshots

### `ios/` and `android/`

Own native platform responsibilities:

- metadata probe implementations
- preview surface implementations
- native playback behavior
- export backends

## Diagnosis Flow

When a bug appears, debug it in this order:

1. Metadata normalization
   - verify imported asset duration/size in `core/media`
2. Engine timeline state
   - verify clip duration and source bounds in `engine/rust_core`
3. Scene projection
   - verify `application` mapping into preview/export nodes
4. Native preview sync
   - compare engine position vs preview position
5. Native export
   - only after preview state is confirmed stable

## Open Issues Mapped To Layers

- `audio noise / choked playback`
  - preview bridge, native playback path, audio node bounds
- `stops near 5s`
  - metadata normalization, fallback duration leakage, engine/preview mismatch
- `lag / black flashes / delayed scrub`
  - scene refresh frequency, preview attach decisions, native surface churn
- `iOS / Android parity`
  - native bridge symmetry and platform capability gaps
- `full export incomplete`
  - native export backends and export graph completeness

## Current Intent

The immediate goal is to keep the UI shell strong while making the runtime path
observable enough that we can fix engine and native playback issues without
guesswork.
