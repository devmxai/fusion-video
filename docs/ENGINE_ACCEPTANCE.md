# Fusion Video Engine Acceptance

## Purpose

This document defines the acceptance checklist for the engine rebuild.

A phase is not closed because the code "looks ready".
A phase closes only when its required behavior is verified on:

- iOS
- Android
- real devices where required

## Universal Rules

- simulator-only success is not enough
- one-platform success is not enough
- UI movement without preview correctness does not count as success
- playback correctness must be measured from timeline truth, not player default behavior
- no feature phase is allowed to hide playback instability behind UX workarounds

## Execution Stabilization Acceptance

This program focus must close before advanced media features resume.

### Required Outcomes

- playback is visibly smooth in normal editing conditions
- preview remains stable during play, pause, seek, and scrub
- audio is consistently present and synchronized
- no recurring black frames appear at common seams
- Android and iOS behave materially the same in core playback scenarios

### Blocking Failure Conditions

The stabilization phase remains open if any of the following is still common:

- repeated playback hitching
- preview freeze while timeline position changes
- scrub that moves UI but not preview frame immediately
- audio dropout during normal playback
- frequent seam hitching between adjacent clips
- playback restarting from incorrect source position after split/delete

## Phase 0 Acceptance — Contract Reset

### Contract Checklist

- all transport commands are defined
- runtime playback events are defined
- scene snapshot contract is defined
- audio snapshot contract is defined
- active clip resolution contract is defined
- continuity and junction classification are defined
- resolved preview payload exists as one authoritative shape

### Implementation Checklist

- Flutter preview path uses backend selection
- legacy preview path still works as fallback
- engine-driven path is available behind feature flag
- iOS and Android use the same command/event vocabulary

## Phase 1 Acceptance — Preview Core

### Functional Tests

- scrub updates preview frame immediately
- seek updates preview to exact expected frame
- pause shows correct pause frame
- pressing play after scrub starts from exact scrubbed position
- play near clip end continues from that exact point
- normal playback does not visibly repeat a single stale frame

### Timeline Integrity Tests

- split one clip into two and play through both parts
- split then delete first segment and play remaining segment from correct source offset
- split multiple times and preserve correct playback mapping for all parts
- trim left/right preserves correct playback start
- reorder clips and preserve deterministic playback mapping

### Platform Closure

- all above behaviors pass on iOS
- all above behaviors pass on Android

## Phase 2 Acceptance — Seam-Safe Playback

### Seam Tests

- split one video into two contiguous parts and play across seam
- split one video into multiple parts and delete middle part
- play across `video -> video` seam with no visible hitch
- play across `video -> image` seam with no black flash
- same-source non-contiguous case behaves correctly without false continuity
- deleting or reordering split parts preserves deterministic continuity

### Visual Closure

- no black frame at common seams
- no visible attachment churn at same-source contiguous seams
- no ordering confusion after split/delete/reorder reconciliation

### Platform Closure

- seam behavior passes on iOS
- seam behavior passes on Android

## Phase 3 Acceptance — Audio Engine

### Audio Tests

- audio is present during normal playback
- audio does not disappear intermittently
- audio does not stutter repeatedly during normal playback
- gain changes apply correctly
- mute applies correctly
- fades apply correctly
- audio remains synchronized through seek, scrub, and seam playback
- audio stays stable across repeated play/pause cycles

### Export Audio Tests

- export audio follows same clip windows and mixer logic
- muted clips remain muted in export
- gain changes match preview behavior

### Platform Closure

- iOS preview audio passes
- Android preview audio passes
- no choked playback on either platform

## Phase 4 Acceptance — GPU Compositor

### Composition Tests

- multiple layers render in correct z-order
- transforms render correctly
- opacity renders correctly
- overlay timing matches clip windows
- image, text, and video overlays compose correctly

### Stability Tests

- no fallback to player-style preview for composed scenes
- preview remains stable during playback and pause
- no frequent black flashes during re-resolution

### Platform Closure

- materially equivalent output on iOS and Android

## Phase 5 Acceptance — Export Parity

### Export Tests

- export completes successfully on iOS
- export completes successfully on Android
- exported result matches preview timing closely
- export handles cancel safely
- export reports progress correctly
- export reports errors clearly

### Parity Tests

- same project exports with approximately matching output on both platforms
- clip timing and offsets are preserved
- seams do not shift unexpectedly in output

## Real Device Acceptance

The following must be tested on real hardware, not only simulator/emulator:

### Android

- one mid-tier Android phone
- playback stability
- scrub responsiveness
- seam continuity
- audio stability
- export smoke test

### iPhone

- one baseline iPhone device
- playback stability
- scrub responsiveness
- seam continuity
- audio stability
- export smoke test

## Performance Targets

These are directionally mandatory even if exact numbers evolve later.

### Playback

- low seek latency
- low scrub latency
- no visible hitch at common seams
- stable playback on mid-tier Android
- preview latency is measurable
- dropped-frame count is measurable

### Audio

- no obvious dropouts in normal playback
- no repeated audio attach/detach artifacts
- audio drop count is measurable
- underrun tracking is measurable

### Render

- dropped frame monitoring exists
- frame readiness is observable
- memory pressure behavior is defined
- no persistent black-frame churn during normal playback

### Export

- throughput is measurable
- cancellation is safe
- failures do not corrupt engine state

## Definition Of Done

A phase is done only when:

- contracts are implemented
- iOS passes required cases
- Android passes required cases
- real-device acceptance is completed where required
- no known blocker remains in playback, seam, or audio behavior for that phase
