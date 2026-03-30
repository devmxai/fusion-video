# Android Real Engine Completion Plan

## Purpose

This document turns the current Android recommendation into an execution plan
that matches the repository as it exists today.

It is intentionally more specific than the high-level engine roadmap.
Its job is to prevent overlap between:

- transport/contracts work
- Android video decode/render work
- Android audio work
- compositor/layout policy work
- timeline thumbnail work
- export work

## Current Code Reality

The recommendation is materially correct.
The current Android stack is still transitional, not final.

Observed current state in code:

- `EngineDrivenPreviewBackend` is already the default Flutter backend:
  - [preview_backend_factory.dart](/Users/mx/Documents/New%20project/fx_flutter_editor/lib/core/preview/preview_backend_factory.dart)
- The Android engine surface is **not** the default Android view path yet:
  - [preview_feature_flags.dart](/Users/mx/Documents/New%20project/fx_flutter_editor/lib/core/preview/preview_feature_flags.dart)
  - [fusion_preview_surface.dart](/Users/mx/Documents/New%20project/fx_flutter_editor/lib/core/preview/fusion_preview_surface.dart)
- The Android engine path exists, but it is still a hybrid transition:
  - [FusionAndroidPreviewEngine.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/FusionAndroidPreviewEngine.kt)
  - [FusionPreviewEnginePlatformView.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/FusionPreviewEnginePlatformView.kt)
  - [AndroidCodecVideoSession.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidCodecVideoSession.kt)
  - [AndroidDecodeScheduler.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidDecodeScheduler.kt)
  - [AndroidPreviewRenderer.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidPreviewRenderer.kt)
- Android audio is not implemented yet:
  - [AndroidAudioEngine.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidAudioEngine.kt)
- Android export is not implemented yet:
  - [AndroidExportPipeline.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidExportPipeline.kt)
- Rust owns useful preview contracts already, but the Rust preview engine is still a contract/state holder, not the final scheduling authority:
  - [preview_engine.rs](/Users/mx/Documents/New%20project/fx_flutter_editor/engine/rust_core/src/preview_engine.rs)

## Recommendation Verdict

The recommendation is correct in direction and should be adopted.

Two practical adjustments are required:

1. Do not hard-delete the legacy Android preview path immediately.
   Keep it as a short-lived fallback until the new engine path passes:
   - import smoke test
   - play/pause smoke test
   - scrub smoke test
   - portrait media layout smoke test

2. Do not start Android export before:
   - video transport is deterministic
   - audio path exists
   - compositor layout rules are stable

So the approved strategy is:

- make the new engine path primary in stages
- isolate the legacy path behind explicit debug fallback
- complete video path first
- complete audio second
- complete compositor/layout third
- complete timeline visuals fourth
- complete export last

## Non-Overlap Rules

These are mandatory.

### Rule 1 — Rust/Bridge Own Time And Intent

Only this layer may define:

- current timeline position
- transport revision
- active clip resolution
- source start/end windows
- continuity class
- scene/audio snapshot intent

This work must stay in:

- [preview_engine.rs](/Users/mx/Documents/New%20project/fx_flutter_editor/engine/rust_core/src/preview_engine.rs)
- [preview_backend.dart](/Users/mx/Documents/New%20project/fx_flutter_editor/lib/core/preview/preview_backend.dart)
- [preview_session_bridge.dart](/Users/mx/Documents/New%20project/fx_flutter_editor/lib/core/preview/preview_session_bridge.dart)
- [engine_driven_preview_backend.dart](/Users/mx/Documents/New%20project/fx_flutter_editor/lib/core/preview/engine_driven_preview_backend.dart)

### Rule 2 — Android Video Path Owns Decode/Render Only

Only the Android execution layer may define:

- decode scheduling
- preroll
- frame buffering
- frame dropping policy
- render submission
- surface/EGL/OpenGL behavior

This work must stay in:

- [FusionAndroidPreviewEngine.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/FusionAndroidPreviewEngine.kt)
- [AndroidCodecVideoSession.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidCodecVideoSession.kt)
- [AndroidDecodeScheduler.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidDecodeScheduler.kt)
- [AndroidPreviewRenderer.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidPreviewRenderer.kt)
- [FusionPreviewEnginePlatformView.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/FusionPreviewEnginePlatformView.kt)

### Rule 3 — Android Audio Path Must Not Hide Inside Video Work

Audio work must remain isolated in:

- [AndroidAudioEngine.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidAudioEngine.kt)

with only minimal bridge wiring elsewhere.

### Rule 4 — Compositor/Layout Policy Is Separate From Decode

Canvas fit rules, portrait behavior, zoom/pan semantics, and base-clip framing
must be specified once and implemented consistently.

Do not mix this policy into:

- Flutter widgets
- ad hoc view fitting
- timeline thumbnail code

### Rule 5 — Timeline Filmstrip Work Must Follow Media Geometry Rules

Thumbnail work comes after:

- media orientation rules
- media fit rules
- source window rules

Otherwise filmstrip fixes become fake fixes.

## Workstreams

### Workstream A — Contract Freeze

Owner:
- Rust + Flutter bridge layer

Write scope:
- `engine/rust_core/src/preview_engine.rs`
- `lib/core/preview/*`
- minimal `MainActivity.kt` / `AppDelegate.swift` bridge code only

Deliverables:
- one authoritative resolved preview payload
- one authoritative transport command model
- one authoritative runtime event model
- clear separation of:
  - `configure payload`
  - `transport command`
  - `runtime metric/event`

Exit criteria:
- Android native path receives full resolved state, not partial mutation logic
- no UI-driven preview correction is needed in Flutter

### Workstream B — Android Path Unification

Owner:
- Android platform integration

Write scope:
- [preview_feature_flags.dart](/Users/mx/Documents/New%20project/fx_flutter_editor/lib/core/preview/preview_feature_flags.dart)
- [fusion_preview_surface.dart](/Users/mx/Documents/New%20project/fx_flutter_editor/lib/core/preview/fusion_preview_surface.dart)
- [MainActivity.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/MainActivity.kt)

Deliverables:
- `fusion_video/preview_surface_engine` becomes primary Android path
- legacy path stays behind explicit fallback flag only
- QA can force either path deliberately

Exit criteria:
- production builds use engine surface by default
- legacy path is fallback-only and not part of normal diagnosis anymore

### Workstream C — Real Android Video Engine

Owner:
- Android video execution

Write scope:
- [FusionAndroidPreviewEngine.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/FusionAndroidPreviewEngine.kt)
- [AndroidCodecVideoSession.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidCodecVideoSession.kt)
- [AndroidDecodeScheduler.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidDecodeScheduler.kt)
- [AndroidMediaIo.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidMediaIo.kt)
- [AndroidPreviewRenderer.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidPreviewRenderer.kt)
- [FusionPreviewEnginePlatformView.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/FusionPreviewEnginePlatformView.kt)

Deliverables:
- `MediaExtractor` source reading
- `MediaCodec` decode path for real playback
- preroll around playhead
- deterministic frame queue
- stale request dropping
- surface/EGL/OpenGL submission path
- no playback restart per frame request

Exit criteria:
- normal playback is smooth on a mid-tier Android device
- playhead motion is stable
- preview no longer feels like repeated frame snapshots
- seek/scrub latency becomes measurable and acceptable

### Workstream D — Android Audio Engine

Owner:
- Android audio execution

Write scope:
- [AndroidAudioEngine.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidAudioEngine.kt)
- audio bridge/runtime hooks only where required

Deliverables:
- audio decode path
- audio buffer
- timeline-synced playback clock usage
- gain/mute/fade
- audio dropout metrics

Exit criteria:
- audio is always present when expected
- no repeated disappear/reappear behavior
- audio stays synchronized with timeline transport

### Workstream E — Compositor Ownership

Owner:
- Rust scene policy + Android renderer integration

Write scope:
- Rust scene/output policy where required
- [FusionPreviewEnginePlatformView.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/FusionPreviewEnginePlatformView.kt)
- [PreviewLayoutPlanner.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/PreviewLayoutPlanner.kt)
- [AndroidPreviewRenderer.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidPreviewRenderer.kt)

Deliverables:
- one explicit media fit policy:
  - contain
  - cover
  - fit-center
  - crop
- correct first-import framing
- correct portrait media behavior
- no layout jump on play/pause
- correct base-clip zoom/pan semantics

Exit criteria:
- imported media appears at expected project framing immediately
- black side bars appear only when intended by compositor policy
- play/pause does not change canvas layout unexpectedly

### Workstream F — Timeline Visual Ownership

Owner:
- media geometry + timeline visual layer

Write scope:
- [AndroidMediaIo.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidMediaIo.kt)
- [MainActivity.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/MainActivity.kt)
- [native_media_thumbnailer.dart](/Users/mx/Documents/New%20project/fx_flutter_editor/lib/core/media/native_media_thumbnailer.dart)
- [timeline_panel.dart](/Users/mx/Documents/New%20project/fx_flutter_editor/lib/features/editor/presentation/widgets/timeline_panel.dart)

Deliverables:
- timeline thumbnails generated with correct orientation
- stable caching policy
- correct source-window mapping after split/delete/trim
- no broken-looking placeholder strips under normal load

Exit criteria:
- clip rectangles show real media frames reliably
- thumbnails match actual content and offsets

### Workstream G — Android Export Completion

Owner:
- Android export pipeline

Write scope:
- [AndroidExportPipeline.kt](/Users/mx/Documents/New%20project/fx_flutter_editor/android/app/src/main/kotlin/com/example/fx_flutter_editor/previewengine/AndroidExportPipeline.kt)
- Rust export planning integration

Deliverables:
- decode -> compose -> encode pipeline
- cancel/progress/error handling
- output timing parity with preview

Exit criteria:
- Android export exists
- export follows engine timing, offsets, and clip windows

## Milestone Order

### Milestone A — Default Path Cleanup

Depends on:
- Workstream A

Includes:
- Workstream B

Must finish before:
- wide device QA
- feature tuning on Android

### Milestone B — Real Video Playback

Depends on:
- Workstream A
- Workstream B

Includes:
- Workstream C

Must finish before:
- serious audio sync work
- compositor policy closure

### Milestone C — Real Audio

Depends on:
- Milestone B transport stability

Includes:
- Workstream D

Must finish before:
- seam-safe signoff
- export parity work

### Milestone D — Compositor Ownership

Depends on:
- Milestone B

Includes:
- Workstream E

Must finish before:
- declaring portrait/canvas behavior fixed
- enabling advanced visual features

### Milestone E — Timeline Visual Reliability

Depends on:
- Milestone D media geometry rules

Includes:
- Workstream F

### Milestone F — Export Parity

Depends on:
- Milestone C
- Milestone D

Includes:
- Workstream G

## Immediate Next Execution Order

These are the next concrete steps from the current repository state.

### Step 1

Freeze contract ownership first.

Do now:
- confirm `ResolvedPreviewPayload` as the only authoritative preview state
- remove any remaining Android-side assumptions that infer clip state outside the payload
- document which fields are authoritative vs advisory

### Step 2

Make Android engine surface the primary path in development builds.

Do now:
- flip `useAndroidEngineSurface` to default `true`
- add an explicit fallback define for legacy Android preview
- keep the legacy path only for smoke comparison

### Step 3

Replace hybrid frame-request playback behavior with one real playback session.

Do now:
- keep `MediaCodec` session stable across transport ticks
- feed decode/render from resolved transport, not repeated frame restarts
- separate paused-frame extraction from active playback decode

### Step 4

Implement Android audio immediately after stable video playback is proven.

Do now:
- replace stub `AndroidAudioEngine`
- bind audio timing to the same transport revision/timebase

### Step 5

Close compositor policy before timeline polish.

Do now:
- define project fit policy
- define portrait behavior
- define play/pause layout invariants
- then align the timeline thumbnail pipeline to the same rules

## Agent Split For Execution

When implementation begins, use parallel agents with disjoint write scopes:

### Agent 1 — Contracts And Bridge

Owns:
- Rust preview contract files
- Flutter preview backend files
- bridge payload/event files

### Agent 2 — Android Video Engine

Owns:
- decode/render/session/platform-view files only

### Agent 3 — Android Audio

Owns:
- audio engine files
- audio runtime metric files

### Agent 4 — Timeline Visuals And Diagnostics

Owns:
- thumbnail generation
- timeline filmstrip cache/render
- runtime metrics display

Rule:
- no agent may edit another agent's write scope in the same round

## Definition Of Done For This Plan

This Android transition is not complete until:

- engine surface is the primary Android path
- legacy preview path is fallback-only
- imported media displays with correct canvas behavior
- playback is smooth on device
- audio is stable and synchronized
- playhead motion is stable
- seek/scrub are accurate
- timeline thumbnails are trustworthy
- export exists on Android
- Android no longer depends on legacy player-style preview behavior for normal editor playback
