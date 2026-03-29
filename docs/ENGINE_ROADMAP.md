# Fusion Video Engine Roadmap

## Purpose

This document translates the engine architecture into execution phases, epics,
deliverables, and closure rules.

This roadmap is authoritative for:

- implementation order
- team prioritization
- cross-platform parity rules
- external code review alignment

## Global Rules

- no media feature is complete on one platform only
- no media feature starts from Flutter hacks
- Rust contract first, adapters second
- current preview path remains fallback only until Phase 2 closes
- Android is not a later port; it is a first-class track
- feature expansion pauses when playback/audio stability is below target

## Current Program Focus — Execution Stabilization

### Why This Phase Exists

The architecture and wiring foundations are now present, but the execution layer
is not yet stable enough for production-grade editing.

Current critical symptoms observed in real use:

- playback hitching and visible stops
- unstable preview continuity
- scrub/seek latency or incorrectness
- intermittent audio loss or stutter
- black frames or seam glitches in some cases

This means the current bottleneck is not feature breadth.
It is execution quality in:

- preview
- audio
- scheduling
- seam handoff

### Program Rules During Stabilization

- no transitions priority
- no effects priority
- no UI polish priority
- no timeline feature expansion priority
- no phase is considered healthy while playback is visibly unstable

### Stabilization Epics

#### S1. Preview Pipeline Determinism

- make preview frame selection timeline-authoritative
- remove dependence on generic player timing behavior
- ensure each visible frame comes from:
  - timeline position
  - clip-local mapped source time
  - decoded frame
  - rendered frame

#### S2. Scheduling And Buffering

- add preroll before playhead
- add frame buffering near playhead
- add next-clip preloading
- prevent decode starvation during normal playback

#### S3. Clock Unification

- Rust transport clock becomes the only runtime clock
- video scheduling derives from Rust clock
- audio scheduling derives from Rust clock
- preview state derives from Rust clock

#### S4. Seam Execution

- no hard reattach for same-source contiguous seams
- controlled preload/preroll for different-source seams
- stable video-image handoff

#### S5. Audio Execution

- real audio decode path
- real audio buffering
- real mixer behavior
- audio transport sync

#### S6. Android Execution Migration

- begin true `MediaCodec` decode path in parallel
- do not expand `MediaPlayer` path beyond fallback needs
- begin EGL/OpenGL preview renderer migration incrementally

#### S7. Metrics And Runtime Diagnostics

- dropped-frame counting
- audio-drop counting
- preview latency tracking
- seek latency tracking
- buffer underrun tracking

## Phase 0 — Contract Reset

### Goal

Replace partial preview state mutation with one authoritative engine contract.

### Epics

#### E0.1 Transport Contract

- define `play`
- define `pause`
- define `seek`
- define `scrub_begin`
- define `scrub_update`
- define `scrub_end`

#### E0.2 Runtime Event Contract

- define `current_timeline_position`
- define `playback_state`
- define `buffering_state`
- define `frame_ready`

#### E0.3 Snapshot Contract

- define `scene_snapshot`
- define `audio_snapshot`
- define `active_clip_resolution`
- define `preview_continuity`
- define `junction_classification`

#### E0.4 Resolved Preview Payload

- create one authoritative payload shape
- remove dependency on partial source/session mutation
- formalize current source and upcoming source

#### E0.5 Backend Selection

- keep fallback path intact
- route new path behind feature flag
- avoid direct screen-to-preview hard wiring

### Deliverables

- Rust contract definitions
- bridge contract definitions
- backend selector
- engine-driven preview bridge
- parity contract available to iOS and Android

### Exit Criteria

- all preview commands/events are represented in one stable contract
- no new preview work depends on ad hoc partial payloads
- fallback path still works

## Phase 1 — Dual-Platform Preview Core

### Goal

Make preview clip-time-authoritative on iOS and Android.

### Epics

#### E1.1 Clip-Local Playback Mapping

- resolve active clip deterministically
- map project time to clip-local source time
- preserve source offsets after split/delete/trim/reorder

#### E1.2 Frame-Accurate Seek/Scrub

- scrub updates preview immediately
- pause frame render comes from engine preview path
- play starts from exact current timeline position
- no visible frame jitter during normal playback

#### E1.3 Stable Preview Binding

- build resolved binding from engine state
- stop relying on generic player defaults
- rebuild preview mapping atomically after timeline edits

#### E1.4 Dual-Platform Adapter Completion

iOS:

- authoritative preview transport adapter

Android:

- authoritative preview transport adapter
- early execution-layer path beyond generic player defaults

### Deliverables

- engine-driven preview binding
- stable seek/scrub/play-from-current-position behavior
- split/delete offset correctness

### Exit Criteria

- scrub updates preview frame immediately
- play always starts from current timeline position
- split/delete does not reset remaining clip to source zero
- iOS and Android pass the same playback-mapping cases

## Phase 2 — Seam-Safe Playback

### Goal

Remove hitching and visual instability at clip junctions.

### Epics

#### E2.1 Junction Resolver Completion

- classify same-source contiguous seams
- classify same-source non-contiguous seams
- classify different-source seams
- classify video-image seams

#### E2.2 Same-Source Contiguous Handling

- avoid hard reattach
- avoid unnecessary reseek
- keep stable attachment if continuity is valid

#### E2.3 Different-Source Handoff

- preload next source
- preroll before seam
- avoid black flash
- avoid visible playback stop at the seam

#### E2.4 Video-Image Handoff

- preload image handoff
- render stable first frame at seam

### Deliverables

- seam-safe resolver behavior
- preload/preroll behavior
- no hard-switch for same-source contiguous seams

### Exit Criteria

- no visible hitch at common seams
- no black frame on video-video or video-image junctions
- split clips from same source play smoothly through seam
- behavior is consistent on iOS and Android

## Phase 3 — Real Audio Engine

### Goal

Replace unstable preview audio with a real synchronized audio path.

### Epics

#### E3.1 Audio Decode Planning

- audio decode per clip
- source windows
- preroll behavior

#### E3.2 Mixer Core

- track gain
- mute
- fade support
- multiple source mixing

#### E3.3 Transport Sync

- lock audio clock to preview transport
- avoid dropouts and choked playback
- maintain stable audio while scrubbing, seeking, and resuming playback

#### E3.4 Export Audio Parity

- same mixer rules apply to export path

### Deliverables

- audio snapshot authority from Rust
- preview audio mixer
- stable audio transport sync

### Exit Criteria

- no periodic audio disappearance
- no obvious room-like duplication artifacts
- stable playback on iOS and Android
- preview and export audio rules match

## Phase 4 — GPU Compositor

### Goal

Move visual composition into a real render graph on both platforms.

### Epics

#### E4.1 Render Graph Activation

- layers
- transforms
- opacity
- z-order

#### E4.2 Android Compositor

- OpenGL ES render path
- decoded frames + render graph

#### E4.3 iOS Compositor Parity

- equivalent GPU-backed composition path

#### E4.4 Overlay/Effect Foundation

- text
- image
- video overlays
- future transition/effect compatibility

### Deliverables

- shared render-graph model
- Android GPU compositor
- iOS compositor parity

### Exit Criteria

- visual result is materially aligned across platforms
- no fallback to player-driven preview for composed scenes

## Phase 5 — Export Parity

### Goal

Make export a first-class engine path on both platforms.

### Epics

#### E5.1 Render Plan For Export

- Rust export plan
- scene/audio parity with preview contracts

#### E5.2 Android Export Path

- decode
- compose
- encode

#### E5.3 iOS Export Alignment

- export contract aligned to same engine plan

#### E5.4 Progress And Errors

- unified progress model
- cancellation
- retry/error reporting

### Deliverables

- dual-platform export contract
- Android export pipeline
- iOS export alignment

### Exit Criteria

- export parity is achieved
- export is not "iOS first, Android later"
- progress and error reporting are stable

## Phase 6 — Advanced Features

### Goal

Build advanced editor features only after core parity and stability exist.

### Epics

- transitions
- effects
- color pipeline
- proxy playback
- advanced performance systems

### Exit Criteria

- no advanced feature closes until it works on both platforms

## Immediate Priority

The next execution priority is:

1. execute `Execution Stabilization` across Phase 1 and Phase 2 immediately
2. stabilize playback and audio before any new feature expansion
3. close Phase 1 fully
4. close Phase 2 fully
5. move into Phase 3 only with stable preview behavior already achieved

If playback, seam continuity, or audio are unstable, feature work must not jump ahead.
