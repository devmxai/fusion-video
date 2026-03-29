# Fusion Video Engine Spec

## Status

This document is the official engine architecture decision for Fusion Video.

It replaces any implicit "iOS first" or "Flutter-driven media behavior" model.
From this point forward, the engine must be built as one logical system with:

- Rust as the source of truth
- iOS and Android implemented in the same phase
- Flutter limited to UI and user intents
- the current preview path treated as temporary fallback only

## Core Decision

Fusion Video will use a:

- parallel engine migration
- feature-flagged rollout
- dual-platform implementation model

It will not use:

- direct rewrite on top of the current preview path
- iOS-first then Android-later execution
- long-term `MediaPlayer` / `TextureView` dependency
- Flutter-owned preview or playback logic

## Current Program Directive

Fusion Video is now in:

- `Execution Stabilization Phase`

This means:

- no feature expansion priority
- no UI polish priority
- no transitions/effects priority

Current engineering focus is exclusively on:

- preview stability
- audio correctness
- transport/scheduling correctness
- seam-safe playback
- real-time playback behavior on iOS and Android

The engine must move from:

- prototype engine

To:

- real-time playback engine

No advanced media feature should be considered for active delivery until playback and audio are stable.

## Architectural Principles

### 1. One Engine, Two Adapters

We are not building two editors.

We are building:

- one engine model
- one timeline model
- one transport model
- one scene model
- one audio model

With:

- one iOS adapter
- one Android adapter

### 2. Rust Is The Single Source Of Truth

Rust owns:

- timeline state
- transport state
- scene snapshot resolution
- audio snapshot resolution
- active clip resolution
- playback mapping
- source offsets
- continuity rules
- seam classification
- preview scheduling intent
- export render planning

Rust must not be reduced to a simple timeline helper.
It is the editor transport authority.

### 2.1 Rust Transport Clock Is Authoritative

There must be one authoritative runtime clock:

- Rust transport clock

The following must derive from that clock:

- video frame resolution
- audio scheduling
- preview state
- seam handoff timing
- scrub/seek/pause frame behavior

The system must not allow:

- video clock drift separate from timeline clock
- audio clock drift separate from timeline clock
- player-native default time to override clip-local resolved time

### 3. Flutter Is UI Only

Flutter owns:

- layout
- gestures
- selection visuals
- sheets
- toolbars
- inspectors
- navigation

Flutter must not own:

- decode behavior
- preview playback rules
- clip-time mapping
- seam handling
- audio transport logic
- export graph logic

Flutter sends intents in.
Engine state and runtime events come out.

### 4. Android Must Become A Real Engine Path

The target Android stack is:

- media I/O: `MediaExtractor`
- decode: `MediaCodec`
- render: `EGL + OpenGL ES 3.x`
- audio: real mixer engine
- export: decode -> compose -> encode pipeline

Android must move to:

- decoded frames + render graph

Not:

- generic player-session behavior

The current `TextureView + MediaPlayer` path may stay only as fallback until the new path closes Phase 2.

No new long-term playback capability should be added to that path beyond what is needed to preserve fallback behavior during migration.

### 5. iOS And Android Move Together

Any engine feature is incomplete unless it works on both:

- iOS
- Android

No feature is considered done when it exists on one platform only.

## Runtime Stack

### Flutter Layer

Responsibilities:

- UI shell
- gesture capture
- intent dispatch
- state presentation

### Bridge Layer

Responsibilities:

- FFI and platform bridge transport
- typed command marshaling
- typed event marshaling
- backend selection

### Rust Core

Responsibilities:

- project model
- timeline operations
- transport authority
- preview resolution
- continuity classification
- render planning
- audio planning
- export planning

### Platform Adapters

iOS:

- AVFoundation
- GPU-backed render path
- native audio/output path

Android:

- MediaExtractor
- MediaCodec
- OpenGL ES
- mixer/output path

## Official Engine Modules

### `project_core`

Owns:

- project schema
- asset registry
- tracks
- clips
- transitions
- effects
- serialization
- migrations

### `timeline_engine`

Owns:

- play
- pause
- seek
- scrub begin
- scrub update
- scrub end
- split
- trim
- delete
- duplicate
- reorder
- continuity-safe reconciliation

### `preview_engine`

Owns:

- active clip resolution
- clip-local playback mapping
- preview transport state
- frame request planning
- preroll planning
- next-clip preload planning
- frame buffer policy
- seam-safe scheduling intent
- preview payload generation

### `render_graph`

Owns:

- layer ordering
- transforms
- opacity
- z-order
- blending
- transitions
- future effect passes

### `audio_engine`

Owns:

- audio decode planning
- audio buffer policy
- mixer planning
- gain
- mute
- fades
- sync with transport

### `export_engine`

Owns:

- export plan
- render plan for export
- encode path selection
- progress model
- cancellation model
- export errors

## Contract Model

The engine contract must be command/event driven.

### Commands

- `play`
- `pause`
- `seek`
- `scrub_begin`
- `scrub_update`
- `scrub_end`

### Runtime State / Events

- `current_timeline_position`
- `playback_state`
- `buffering_state`
- `frame_ready`

### Snapshots

- `scene_snapshot`
- `audio_snapshot`
- `active_clip_resolution`
- `preview_continuity`
- `junction_classification`

### Resolved Preview Payload

The preview bridge must move toward one authoritative payload instead of partial mutations.

Required contents:

- project time
- clip-local source time
- source window
- active clip ids
- current source
- upcoming source
- scene snapshot
- audio snapshot
- continuity class

Continuity classes:

- `same-source-contiguous`
- `same-source-non-contiguous`
- `different-source`
- `video-to-image`

## Seam-Safe Playback Rules

### Same-Source Contiguous

If two adjacent clips come from the same source and are source-contiguous:

- do not treat the seam as a hard source switch
- do not reattach unnecessarily
- do not reseek to asset time zero
- do not reset decoder state unless continuity is actually broken
- keep attachment stable where possible

### Same-Source Non-Contiguous

If the same source is reused but offsets are not contiguous:

- preserve clip-local mapping
- allow controlled reseek
- do not confuse this case with contiguous seams

### Different-Source

If the next clip is a different source:

- preload next visual source before seam
- preroll before seam becomes visible
- prepare the handoff before the current clip ends
- avoid black flash and attachment churn

### Video-To-Image

If the next visible node is an image:

- preload image payload
- render handoff without black frame
- do not fall back to player-style empty frame transitions

## Migration Strategy

### Feature Flag

The migration must stay behind:

- `FUSION_USE_ENGINE_DRIVEN_PREVIEW`

Rules:

- `false` = current preview path remains fallback
- `true` = engine-driven preview path is used

### Parallel Engine Rule

The new engine path must be built in parallel.

We do not stop the project and rewrite everything in place.
We migrate capability by capability behind stable contracts.

## Development Rules

### Mandatory Rules

- every media feature starts from contract definition
- every media feature is implemented on iOS and Android in the same phase
- Rust API is defined before adapter behavior
- no new long-term feature may be built on `MediaPlayer`
- no new long-term feature may be built on `TextureView`
- no merge for media features without dual-platform validation
- current preview path remains temporary fallback only
- engine parity and preview stability are higher priority than new UI features
- feature expansion is paused while execution stabilization remains open

### Anti-Patterns To Avoid

- partial preview updates that compete with each other
- Flutter deciding playback mapping locally
- player defaults overriding clip-local time
- iOS behavior shipped first with Android deferred
- UI-only workarounds for preview/audio defects
- treating playback hitching as acceptable while adding new features

## Stabilization Priorities

The immediate execution priorities are:

1. deterministic preview pipeline
2. preroll + buffering around playhead
3. seam-safe handoff behavior
4. real audio engine path
5. authoritative clock unification
6. Android execution-layer migration beyond generic player behavior
7. diagnostics converted into measurable runtime metrics

## Success Criteria

The engine direction is correct only if it produces:

- frame-accurate scrub
- play-from-current-position correctness
- stable split/delete/reorder playback mapping
- seam-safe preview continuity
- stable audio without dropouts
- visual parity across iOS and Android
- export parity across iOS and Android

## Implementation Order

The implementation order is defined in:

- [ENGINE_ROADMAP.md](/Users/mx/Documents/New%20project/fx_flutter_editor/docs/ENGINE_ROADMAP.md)

Acceptance and exit criteria are defined in:

- [ENGINE_ACCEPTANCE.md](/Users/mx/Documents/New%20project/fx_flutter_editor/docs/ENGINE_ACCEPTANCE.md)
