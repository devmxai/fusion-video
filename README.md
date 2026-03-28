# Fusion Video

Fusion Video is a Flutter-based mobile video editor prototype for iOS and Android.

The current goal of this repository is to build the editor UI, timeline behavior, and engine foundation first, then continue toward a native-grade preview/render/export engine that can scale into a production editor.

## Current Status

This repository is no longer a plain mockup.

The project currently includes:

- A custom mobile editor shell in Flutter
- A real bottom-sheet based media import flow
- Real media picking for video, image, and audio
- Timeline insertion for imported assets
- A selectable clip-based timeline
- Working editor controls for:
  - play / pause
  - split
  - trim left
  - trim right
  - delete
  - duplicate
- A real preview path for imported video/image in the Flutter preview stage
- A Rust engine foundation connected through FFI
- Rust timeline state operations already wired into Flutter

## What Has Been Built

### Mobile Editor UI

The Flutter UI currently includes:

- Top app bar
- Preview stage
- Embedded tools bar
- Scrollable, zoomable timeline
- Centered playhead workflow
- Bottom media dock
- Media import bottom sheet

The mobile timeline supports:

- Horizontal scrubbing
- Vertical scrolling for multiple tracks
- Pinch zoom on timeline scale
- Adaptive ruler labels
- Clip selection with highlighted state
- Split bridge visualization

### Real Import Flow

The app can now import:

- Video from the device media library
- Images from the device media library
- Audio from file picker

Imported assets are stored in the in-app asset list and can be inserted into the timeline with their correct media type.

### Preview Behavior

The preview shell is no longer a static placeholder.

For imported visual assets:

- Video preview uses `video_player`
- Image preview uses the imported file directly
- The first inserted visual asset determines the working aspect ratio
- The preview area follows the imported media aspect ratio instead of staying fixed to a mock ratio

### Engine Foundation

Fusion Video is intentionally split into:

- Flutter for UI and interaction
- Rust for engine state and timeline operations
- Native platform bridges for future preview and rendering work

Rust currently handles the foundation for:

- project creation
- transport state
- play / pause / seek
- split
- trim left / trim right
- delete
- duplicate
- timeline snapshots returned to Flutter

## Repository Structure

### Flutter App

- `lib/features/editor/`
  - mobile editor screen
  - preview widgets
  - tools bar
  - timeline UI
  - media dock / bottom sheet

### Engine Layer

- `lib/core/engine/`
  - engine contract
  - FFI bridge
  - runtime bridge / controller

### Rust Core

- `engine/rust_core/`
  - timeline state
  - project state
  - FFI exports

### Native Platform Glue

- `ios/Runner/`
- `android/app/`

### Docs

- `docs/ENGINE_SPEC.md`
- `docs/ENGINE_BUILD.md`

## How To Run

### Flutter iOS

```bash
cd "/Users/mx/Documents/New project/fx_flutter_editor"
flutter run -d "iPhone 16e"
```

Useful run keys:

- `r` hot reload
- `R` hot restart

### Flutter Analyze

```bash
cd "/Users/mx/Documents/New project/fx_flutter_editor"
flutter analyze
```

### Flutter Tests

```bash
cd "/Users/mx/Documents/New project/fx_flutter_editor"
flutter test
```

### Rust Engine Tests

```bash
cd "/Users/mx/Documents/New project/fx_flutter_editor"
cargo test --manifest-path engine/rust_core/Cargo.toml
```

## Engine Build Scripts

The repository already contains engine build scripts for future native integration:

- `scripts/setup_engine_toolchain.sh`
- `scripts/build_engine_host.sh`
- `scripts/build_engine_ios.sh`
- `scripts/build_engine_android.sh`
- `scripts/build_engine_all.sh`

See:

- `docs/ENGINE_BUILD.md`

## What Is Still In Progress

The project is advancing from UI-plus-engine-state into full native preview/render behavior.

The biggest remaining milestones are:

- real native preview surface playback path
- full asset hydration into engine state
- real audio/video sync engine
- multi-track compositing
- export pipeline
- performance tuning for mobile-class devices

## Design Direction

The long-term architecture is intentionally designed to support:

- transitions
- camera moves
- color adjustments
- keyframes
- AI-assisted tools
- image generation workflows
- lip sync workflows
- scalable export pipelines

The editor is being built with expansion in mind, not as a temporary mock app.

## Notes

- The repository is focused on mobile-first editor behavior.
- The current implementation prioritizes architecture and correctness before heavy rendering optimization.
- Flutter is the front-end layer only; the engine is being moved toward native-grade behavior through Rust plus platform-native rendering paths.

## Project Name

This repository is the dedicated Flutter editor project:

- Fusion Video

