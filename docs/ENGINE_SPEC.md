# Fusion Video Engine Spec

## Purpose

This document defines the first stable architecture for the local editing engine
that will power Fusion Video on iOS and Android.

Flutter is responsible for:

- editor shell UI
- timeline gestures and toolbars
- panels, sheets, and user flows
- platform navigation and app lifecycle

The engine is responsible for:

- project state execution
- playback clock
- seek and scrub
- frame-accurate timeline operations
- decode scheduling
- audio mixing
- compositing
- export

The goal is to make the engine expandable enough for future features like:

- camera-style transitions
- push and pan transitions
- color adjustment stacks
- keyframes
- AI-assisted tools
- image generation
- lip sync upgrades
- proxy playback and adaptive preview quality

## Design Goals

1. Local-first execution
   - No server dependency for editing, playback, or export.
2. Frame-accurate timeline model
   - Split, trim, seek, and export must resolve to stable timeline positions.
3. GPU-first preview path
   - The preview path must prefer hardware decode and hardware composition where possible.
4. Expandable render graph
   - Effects and transitions must be attachable as graph nodes rather than hardcoded one-offs.
5. Stable Flutter boundary
   - Flutter should talk to a narrow, versioned engine API instead of touching media internals.
6. Predictable performance
   - Playback quality should degrade gracefully before UI responsiveness is lost.

## Non-Goals For The First Engine MVP

- AI rendering inside the engine
- cloud sync
- collaborative editing
- advanced motion tracking
- desktop support

## Runtime Layers

### 1. Flutter UI Layer

Owns:

- layout
- gestures
- selection
- editor tools
- bottom sheets
- inspector panels

Does not own:

- decode
- audio playback pipeline
- final export graph

### 2. Engine Bridge Layer

Owns:

- FFI bindings
- request/response marshaling
- typed engine events
- handle management

### 3. Engine Core Layer

Recommended implementation:

- Rust as the orchestration core
- platform codec/render adapters behind the core

Owns:

- project graph
- track/clip/effect graph
- transport clock
- preview scheduling
- frame cache and proxy policy

### 4. Platform Media Layer

iOS:

- AVFoundation
- VideoToolbox
- Metal

Android:

- MediaCodec
- MediaExtractor or Media3
- OpenGL ES or Vulkan

### 5. Export Layer

Preferred path:

- hardware encoder when available

Fallback path:

- FFmpeg-based software or format fallback

## Core Modules

### project_core

Canonical project state.

Types:

- Project
- Asset
- Track
- Clip
- Effect
- Transition
- Keyframe

Responsibilities:

- serialization
- versioning
- validation
- migration

### timeline_engine

Responsibilities:

- play
- pause
- seek
- scrub
- split
- trim
- duplicate
- delete
- ripple rules
- snapping model

### preview_engine

Responsibilities:

- decode scheduling around playhead
- frame requests
- pause frame rendering
- scrub frame rendering
- playhead-driven preview updates

### render_graph

Responsibilities:

- layer ordering
- transforms
- opacity
- blend/composite passes
- transition passes
- future color and adjustment passes

### audio_engine

Responsibilities:

- decode audio
- timeline sync
- per-track mute
- volume and gain
- preview mixer
- export mixer

### media_io

Responsibilities:

- inspect imported media
- generate proxies
- generate thumbnails
- generate waveform summaries

### export_engine

Responsibilities:

- build export render plan
- choose hardware/software encoding path
- monitor progress
- emit export events

## Canonical Data Model

### Asset

Represents source media imported into the project.

Fields:

- id
- uri
- media type
- width
- height
- duration
- audio channels
- sample rate
- rotation metadata
- proxy status

### Track

Represents a lane of timeline content.

Fields:

- id
- kind: video, image, audio, text, lip_sync, effect
- muted
- visible
- locked
- order index

### Clip

Represents a time-bounded placement of an asset or generated element.

Fields:

- id
- track id
- asset id or generated payload id
- timeline start
- duration
- source in
- source duration
- transform snapshot
- transition in/out ids
- selection state is UI-only and must stay outside engine state

### Effect

Effects attach to clip or track scopes.

Examples:

- transform
- opacity
- crop
- color adjustment
- blur
- sharpen
- LUT

### Transition

Transition is a first-class object, not a visual shortcut.

Fields:

- id
- left clip id
- right clip id
- duration
- type
- parameter bag

This keeps room for:

- dissolve
- wipe
- push left/right/up/down
- zoom camera transitions

## Playback Model

The engine owns the authoritative transport clock.

Important rules:

- Flutter does not calculate playback time on its own once the engine is live.
- Flutter sends intent:
  - play
  - pause
  - seek
  - scrub begin
  - scrub update
  - scrub end
- Engine sends back:
  - current timeline position
  - playback state
  - buffering state
  - visible frame readiness

### Preview Strategy

For smooth mobile playback:

- decode ahead around playhead
- maintain a short frame cache window
- use lower-cost proxy frames during high-velocity scrubbing when needed
- always render an explicit last-good frame instead of flashing black

## Performance Strategy

### Tier 1

Required for MVP:

- visible-range thumbnails only
- waveform generation in background isolate or engine worker
- decode-ahead window
- frame cache near playhead
- audio preroll

### Tier 2

Next step:

- proxy media generation
- adaptive preview resolution
- clip prewarm
- idle-time cache fill

### Tier 3

For large projects:

- smart memory pressure policy
- reusable texture pools
- background export worker

## Transition And Effects Strategy

The render graph must support:

- clip-local effects
- track-level effects
- project-level adjustments
- transitions between adjacent clips

Every future visual feature should fit as one of:

- source node
- transform node
- effect node
- transition node
- output node

This prevents rewrite later when adding:

- push in
- push up
- pan left/right
- cinematic blur transitions
- color grading chains

## AI Readiness Strategy

AI tools must live above the engine, not inside the transport/render core.

Recommended AI architecture:

- AI requests generate assets, keyframes, captions, or effect presets
- engine consumes the results as normal project data

Examples:

- generated image becomes an Asset
- smart caption becomes text clips
- AI transition suggestion becomes a Transition preset
- AI lip sync becomes generated timeline data

## Folder Strategy

This repo will use:

- `docs/` for architecture and build specs
- `engine/rust_core/` for the orchestration core
- `lib/core/engine/` for Flutter-side contracts and bridge code

## Delivery Phases

### Phase 1

Spec and contracts only.

Deliverables:

- engine spec
- Rust folder scaffold
- Flutter FFI contract scaffold

### Phase 2

Single-video preview MVP.

Deliverables:

- open local video
- play/pause
- seek
- scrub
- pause frame render

### Phase 3

Editing core.

Deliverables:

- split
- trim left/right
- delete
- duplicate
- undo/redo hooks

### Phase 4

Multi-track compositing.

Deliverables:

- image track
- text track
- audio track
- basic transforms

### Phase 5

Transitions and adjustments.

### Phase 6

Export pipeline.

## First Sprint Recommendation

The first implementation sprint should not attempt transitions or export.

It should build only:

- engine project handle
- asset registration
- transport clock
- preview playback for one video clip
- seek and scrub callbacks

If this sprint is stable, the rest of the editor can grow safely on top of it.

## Official Migration Rule

The engine migration path is now:

- parallel backend, not direct rewrite
- Rust contracts first
- iOS and Android adapters in the same phase
- Flutter UI selects a preview backend but does not own media logic

Current implementation rule:

- `FUSION_USE_ENGINE_DRIVEN_PREVIEW=false`
  - uses the current native preview session path as fallback
- `FUSION_USE_ENGINE_DRIVEN_PREVIEW=true`
  - uses the new engine-driven preview bridge and transport commands

This flag exists so the repository can evolve toward:

- resolved preview payloads
- command/event transport
- codec/render/audio adapters behind one engine-owned contract
