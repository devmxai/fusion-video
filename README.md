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

## Checkpoint Summary (2026-03-29)

The project is currently at a strong mobile-editor checkpoint:

- Flutter mobile UI is roughly `70%` ready as an editor shell
- The timeline, tools, bottom media dock, and mobile interaction model are already built as a working prototype
- The Rust engine foundation, FFI bridge, and native preview bridges for iOS/Android are already in place
- The Flutter editor is now split more cleanly into `presentation`, `application`, `core`, and native layers so runtime bugs can be isolated instead of chased inside one giant screen file
- Basic editor actions already exist at the UI/engine-state level:
  - play / pause / seek
  - split
  - trim left / trim right
  - delete
  - duplicate
- The next major phase is not more UI mockup work; it is stabilizing the real preview/render/audio engine path

What is considered done enough for the current checkpoint:

- mobile editor shell
- mock-to-engine timeline behavior
- real media import foundation
- native preview foundation
- engine folder structure and build setup

What is still considered actively under construction:

- stable preview playback
- clean audio playback
- duration normalization
- true compositor/render path
- export parity across iOS and Android

### Architecture Phase Status

- `Phase 0`: completed
  - Flutter = UI
  - Rust = orchestration / timeline / transport
  - iOS/Android native = preview plumbing
- `Phase 1`: completed
  - `video_player` removed
  - native media-backed preview path in place
- `Phase 2`: completed in foundation form
  - asset registry inside the engine
  - timeline clips bound to real imported assets
  - clip source offsets wired into preview timing
  - clip-bounded preview playback and project duration synchronization
- `Phase 3`: in active progress
  - composition scene snapshots
  - native multi-node preview on iOS
  - audio scene foundation and clip gain/mute support
  - export foundation for iOS
- `Phase 4+`: not started yet
  - transitions
  - full export graph
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

At the moment, the mobile UI is in a strong prototype state and is usable enough for interaction and layout iteration, while the native-grade engine is still in active construction.

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
- Flutter `application` helpers for scene mapping, metadata normalization, and runtime diagnostics
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

This is still a preview/compositor-foundation implementation, not yet the final production compositor/render/export engine.

The repository now also includes a parallel engine-driven preview migration path behind:

- `--dart-define=FUSION_USE_ENGINE_DRIVEN_PREVIEW=true`

This new path is intended to move preview toward:

- resolved preview payloads
- command/event transport
- backend selection instead of hard-wiring the editor screen to one preview implementation
- future MediaCodec/OpenGL ES and iOS-equivalent engine adapters without rewriting Flutter UI again

Current migration checkpoint in this repository already includes:

- a Flutter preview backend selector with legacy fallback still intact
- an engine-driven preview backend that consumes one authoritative payload shape
- native `preview_engine` / `preview_events` bridge channels on iOS and Android
- Android preview-engine scaffolding modules for:
  - media I/O
  - decode scheduling
  - preview rendering
  - audio engine
  - export pipeline
- iOS preview-engine host scaffolding mirroring the same transport contract
- Rust module boundaries for:
  - `project_core`
  - `timeline_engine`
  - `preview_engine`
  - `render_graph`
  - `audio_engine`
  - `export_engine`

This is intentionally a migration checkpoint, not the final Android professional engine yet. The production target remains:

- Rust-owned timeline/state/transport authority
- Android decode/render/audio/export adapters behind one engine contract
- iOS parity in the same implementation phase, not as a later rewrite

### Compositor Foundation

The engine now exposes scene-oriented data instead of a single flat media binding.

This foundation already includes:

- composition node snapshots from Rust
- audio node snapshots from Rust
- clip start/end bounds
- source start/end offsets
- transform / opacity / z-order data
- native preview composition on iOS for:
  - base video
  - secondary video overlays
  - image overlays
  - text / lip sync native placeholder nodes

### Export Foundation

The project also now includes a first export foundation for iOS.

This export layer can currently:

- build an export request from the active engine scene
- pass scene and audio snapshot data into native iOS export code
- create an `AVMutableComposition`
- export a first scene-aware video result with:
  - base video
  - audio controls
  - static overlays for image / text / lip sync

This is not yet the final full timeline export graph.

## Project Split For Debugging

The current editor/runtime split is now organized as:

- `lib/features/editor/presentation/`
  - widgets, layout, gestures, and editor shell UI
- `lib/features/editor/application/`
  - scene projection for preview/export
  - media metadata normalization
  - runtime diagnostics/warnings
- `lib/core/`
  - engine, preview, export, and media bridge contracts
- `engine/rust_core/`
  - canonical timeline/project state and snapshots
- `ios/Runner/` and `android/app/`
  - platform probes, preview glue, and export backends

The diagnostic split document for this checkpoint is:

- `docs/PROJECT_SPLIT.md`

## Runtime Diagnostics

To make playback bugs easier to isolate, the editor now has a debug-only
runtime diagnostics surface that shows:

- engine time vs preview time
- selected clip and active preview source
- composition/audio node counts
- warnings for transport mismatch
- warnings for duration mismatch
- warnings for possible unresolved `5s` fallback duration

The goal is to make `5s clamp`, `scrub lag`, and preview desync measurable
instead of inferred.

## Known Open Issues

These issues are currently considered active and unresolved:

- Timeline preview audio can still sound choked / noisy in some playback paths, especially after clips are inserted into the timeline
- Some playback flows can still behave as if there is a `5s` duration clamp due to incomplete normalization between Flutter defaults, imported media metadata, and engine timeline duration
- Scrubbing / preview playback still needs a real performance pass to eliminate lag, black flashes, and delayed frame updates
- Clip seam playback is still not production-safe: after `split`, and at `video -> video` or `video -> image` joins, the preview can hitch, distort briefly, or transition harshly instead of staying smooth
- On Android, pressing `play` after pausing and moving the playhead forward can still restart from the beginning of the source instead of respecting the new timeline position
- Split clips are still not fully trustworthy as real timeline segments: after `split`, some playback paths still behave as if each resulting part is reading from the source start rather than its true clip-local offset
- On Android, horizontal timeline scrubbing can move the UI ruler/track while the preview canvas lags behind the finger and does not update with the same smoothness seen on iOS simulator
- During playback, the visible video motion can still show small jitter / unstable movement instead of steady frame-to-frame transport
- Native preview behavior is not yet fully symmetric between iOS and Android
- Android export is still not implemented; export foundation currently exists on iOS first
- The Rust engine is connected through FFI, but real production playback/rendering is still only partially delegated to the engine
- Audio mixing, transitions, color adjustments, and AI tools are not yet implemented in the real engine path
- Audio metadata probing and duration propagation still need to be completed end-to-end so imported audio/video always use their real source duration
- The current preview path is still good for architecture validation, but not yet at production-grade smoothness on device

## Current Focus

The current technical focus is:

- stabilizing native preview playback
- removing timeline duration mismatches
- fixing audio quality during timeline playback
- preparing the engine for a true render/mixer pipeline
- keeping Flutter as UI/front-end only

## Current Workspace Paths

Project root on this Mac:

- `/Users/mx/Documents/New project/fx_flutter_editor`

Primary README:

- `/Users/mx/Documents/New project/fx_flutter_editor/README.md`

Engine specification:

- `/Users/mx/Documents/New project/fx_flutter_editor/ENGINE_SPEC.md`

Canonical engine spec source:

- `/Users/mx/Documents/New project/fx_flutter_editor/docs/ENGINE_SPEC.md`

Engine build notes:

- `/Users/mx/Documents/New project/fx_flutter_editor/docs/ENGINE_BUILD.md`

## Repository Structure

### Flutter App

- `lib/features/editor/`
  - mobile editor screen
  - application helpers
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

- `ENGINE_SPEC.md`
- `docs/PROJECT_SPLIT.md`
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
- stable real-time playback on device and simulator
- real audio/video sync engine
- full multi-track compositing
- full scene-driven export graph
- performance tuning for mobile-class devices

The next major architectural milestone is:

- `Phase 3: Compositor Engine`
  - multi-layer video/image/audio/text rendering
  - GPU-backed composition
  - engine-owned visual output instead of single-source preview handoff

## Current Blocking Runtime Issues

The current top blocking issues are now concentrated in the runtime preview path rather than the editor shell itself.

Current symptoms under active investigation:

- imported video can still stop around the `5s` mark even when the source is longer
- playback can stutter and feel unsmooth during transport updates
- audio can sound noisy, choked, or otherwise unclear in some timeline playback paths
- scrub / seek can still cause black flashes or delayed visual response in some cases
- seam points are still a major blocker: when a clip is split, or when playback crosses `video -> video` / `video -> image`, the join can lag and briefly deform the picture instead of playing through smoothly
- after `pause -> seek forward -> play`, playback can still jump back to the beginning of the source instead of starting from the requested timeline time
- after `split`, each resulting clip can still behave as if it is not fully anchored to its real timeline/source offset, which makes cuts feel visually incorrect and not truly timeline-accurate
- on Android specifically, timeline scrolling/scrubbing can move the timeline UI while the preview canvas trails behind and does not track the finger with iOS-level smoothness
- even when playback starts correctly, motion on the preview surface can still show small jitter / instability during transport

Important clarification:

- media import itself is real
- timeline insertion itself is real
- the current unresolved problems are in the transport / native preview / audio synchronization layers

This checkpoint is intentionally documented before deeper engine/runtime work on:

- engine clock ownership
- duration recomputation rules
- audio duplication / gain path correctness
- iOS native preview sync
- Android native preview parity
- simulator/device transport behavior

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
