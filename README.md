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
- A native preview path for imported video/image on iOS and Android
- A Rust engine foundation connected through FFI
- Rust timeline state operations already wired into Flutter
- An engine asset registry and clip-to-asset binding model
- Clip-aware preview playback using:
  - asset id
  - source offset
  - source start / end bounds

### Architecture Phase Status

- `Phase 0`: completed
  - Flutter = UI
  - Rust = orchestration / timeline / transport
  - iOS/Android native = preview plumbing
- `Phase 1`: completed
  - `video_player` removed
  - native media-backed preview path in place
- `Phase 2`: in active progress
  - `Sprint 1`: asset registry inside the engine
  - `Sprint 2`: timeline clips bound to real imported assets
  - `Sprint 3`: clip source offsets wired into preview timing
  - `Sprint 4`: clip-bounded preview playback and project duration synchronization
- `Phase 3+`: not started yet
  - compositor
  - transitions
  - export engine
  - performance pass

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

The import side now feeds the engine asset registry rather than staying as Flutter-only UI state.

### Preview Behavior

The preview shell is no longer a static placeholder or a `video_player` wrapper.

For imported visual assets:

- Video preview uses native platform preview surfaces on iOS and Android
- Image preview uses the imported file directly
- The first inserted visual asset determines the working aspect ratio
- The preview area follows the imported media aspect ratio instead of staying fixed to a mock ratio
- The active timeline clip drives preview selection
- Split and trim now affect preview source timing through clip-local offsets
- Preview playback is bounded to clip start/end instead of always treating the full source as one flat asset

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
- asset registry
- clip asset binding
- clip source offsets
- project duration recomputation from timeline state
- timeline snapshots returned to Flutter

Flutter currently reads real timeline state from the engine and resolves active visual bindings from engine-owned clip data.

### Native Preview Layer

The current native preview stack is:

- iOS:
  - `AVPlayerLayer`
  - native media probing through `AVFoundation`
- Android:
  - `TextureView + MediaPlayer`
  - native media probing through `MediaMetadataRetriever`

This is still a preview phase implementation, not yet the final compositor/render/export engine.

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

- final transport synchronization between engine timeline and native preview
- full asset hydration into engine state
- real audio/video sync engine
- multi-track compositing
- transition graph
- export pipeline
- performance tuning for mobile-class devices

The next major architectural milestone is:

- `Phase 3: Compositor Engine`
  - multi-layer video/image/audio/text rendering
  - GPU-backed composition
  - engine-owned visual output instead of single-source preview handoff

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
- The current preview path is real and native, but it is not yet the final compositor/export engine.

## Project Name

This repository is the dedicated Flutter editor project:

- Fusion Video
