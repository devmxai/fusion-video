import 'dart:async';

import 'package:flutter/material.dart';

import 'fusion_preview_surface.dart';
import 'preview_backend.dart';
import 'preview_session_bridge.dart';

class EngineDrivenPreviewBackend extends FusionPreviewBackend {
  EngineDrivenPreviewBackend({
    required this.projectId,
  }) {
    _subscribeToRuntimeEvents();
  }

  int projectId;
  PreviewBackendState _state = const PreviewBackendState();
  StreamSubscription<PreviewRuntimeEvent>? _eventsSubscription;

  @override
  PreviewBackendState get state => _state;

  @override
  Future<void> bindProject(int projectId) async {
    if (this.projectId == projectId) {
      return;
    }
    this.projectId = projectId;
    await _subscribeToRuntimeEvents();
    if (_state.projectWidth != null && _state.projectHeight != null) {
      await applyResolvedPayload(
        ResolvedPreviewPayload(
          projectId: projectId,
          positionSeconds: _state.positionSeconds,
          isPlaying: _state.isPlaying,
          transportRevision: _state.transportRevision,
          source: _state.source,
          upcomingSource: _state.upcomingSource,
          projectWidth: _state.projectWidth ?? 0,
          projectHeight: _state.projectHeight ?? 0,
          compositionNodes: _state.compositionNodes,
          audioNodes: _state.audioNodes,
          baseClipIds: _state.baseClipIds,
          baseClipId: _state.baseClipId,
          selectedClipId: _state.selectedClipId,
          baseAudioGain: _state.baseAudioGain,
          baseAudioMuted: _state.baseAudioMuted,
          continuityKind: PreviewContinuityKind.differentSource,
        ),
      );
    }
  }

  @override
  Future<void> applyResolvedPayload(ResolvedPreviewPayload payload) async {
    _state = _state.copyWith(
      source: payload.source,
      clearSource: payload.source == null,
      upcomingSource: payload.upcomingSource,
      clearUpcomingSource: payload.upcomingSource == null,
      compositionNodes: payload.compositionNodes,
      audioNodes: payload.audioNodes,
      projectWidth: payload.projectWidth,
      projectHeight: payload.projectHeight,
      baseClipId: payload.baseClipId,
      clearBaseClipId: payload.baseClipId == null,
      baseClipIds: payload.baseClipIds,
      selectedClipId: payload.selectedClipId,
      clearSelectedClipId: payload.selectedClipId == null,
      baseAudioGain: payload.baseAudioGain,
      baseAudioMuted: payload.baseAudioMuted,
      isReady: payload.source != null,
      isPlaying: payload.isPlaying,
      transportRevision: payload.transportRevision,
      positionSeconds: payload.positionSeconds,
      durationSeconds: payload.source?.effectiveDurationSeconds ?? 0,
      contentSize:
          (payload.source?.width != null && payload.source?.height != null)
              ? Size(
                  payload.source!.width!.toDouble(),
                  payload.source!.height!.toDouble(),
                )
              : null,
      clearContentSize: payload.source == null,
      isFrameReady: payload.source != null,
    );
    notifyListeners();
    await FusionPreviewSessionBridge.configurePreviewEngine(payload);
  }

  @override
  Future<void> syncTransport({
    required double positionSeconds,
    required bool isPlaying,
    bool force = false,
  }) async {
    final targetSeconds = positionSeconds < 0 ? 0.0 : positionSeconds;
    final previousPlaying = _state.isPlaying;
    final shouldPush = force ||
        isPlaying != _state.isPlaying ||
        (targetSeconds - _state.positionSeconds).abs() > 0.001;
    final nextRevision = _state.transportRevision + (shouldPush ? 1 : 0);
    _state = _state.copyWith(
      positionSeconds: targetSeconds,
      isPlaying: isPlaying,
      transportRevision: nextRevision,
    );
    notifyListeners();
    if (!shouldPush) {
      return;
    }

    await FusionPreviewSessionBridge.dispatchPreviewCommand(
      projectId: projectId,
      transportRevision: nextRevision,
      command: PreviewTransportCommand(
        kind: !isPlaying
            ? PreviewTransportCommandKind.pause
            : (previousPlaying
                ? PreviewTransportCommandKind.seek
                : PreviewTransportCommandKind.play),
        positionSeconds: targetSeconds,
        isPlaying: isPlaying,
      ),
    );
  }

  @override
  Future<void> attachSource(
    PreviewSource? source, {
    bool autoplay = false,
    PreviewSource? upcomingSource,
  }) async {
    final shouldKeepPlaying =
        source != null && (autoplay || (_state.isReady && _state.isPlaying));
    final payload = ResolvedPreviewPayload(
      projectId: projectId,
      positionSeconds: _state.positionSeconds,
      isPlaying: shouldKeepPlaying,
      transportRevision: _state.transportRevision,
      source: source,
      upcomingSource: upcomingSource,
      projectWidth: _state.projectWidth ?? 0,
      projectHeight: _state.projectHeight ?? 0,
      compositionNodes: _state.compositionNodes,
      audioNodes: _state.audioNodes,
      baseClipIds: _state.baseClipIds,
      baseClipId: _state.baseClipId,
      selectedClipId: _state.selectedClipId,
      baseAudioGain: _state.baseAudioGain,
      baseAudioMuted: _state.baseAudioMuted,
      continuityKind: PreviewContinuityKind.differentSource,
    );
    await applyResolvedPayload(payload);
  }

  @override
  Future<void> updateSource(
    PreviewSource? source, {
    PreviewSource? upcomingSource,
  }) async {
    final payload = ResolvedPreviewPayload(
      projectId: projectId,
      positionSeconds: _state.positionSeconds,
      isPlaying: _state.isPlaying,
      transportRevision: _state.transportRevision,
      source: source,
      upcomingSource: upcomingSource,
      projectWidth: _state.projectWidth ?? 0,
      projectHeight: _state.projectHeight ?? 0,
      compositionNodes: _state.compositionNodes,
      audioNodes: _state.audioNodes,
      baseClipIds: _state.baseClipIds,
      baseClipId: _state.baseClipId,
      selectedClipId: _state.selectedClipId,
      baseAudioGain: _state.baseAudioGain,
      baseAudioMuted: _state.baseAudioMuted,
      continuityKind: PreviewContinuityKind.differentSource,
    );
    await applyResolvedPayload(payload);
  }

  @override
  Future<void> updateCompositionScene({
    required int projectWidth,
    required int projectHeight,
    required List<PreviewCompositionNode> nodes,
    required List<PreviewAudioNode> audioNodes,
    String? baseClipId,
    List<String>? baseClipIds,
    String? selectedClipId,
    double baseAudioGain = 1,
    bool baseAudioMuted = false,
  }) async {
    final payload = ResolvedPreviewPayload(
      projectId: projectId,
      positionSeconds: _state.positionSeconds,
      isPlaying: _state.isPlaying,
      transportRevision: _state.transportRevision,
      source: _state.source,
      upcomingSource: _state.upcomingSource,
      projectWidth: projectWidth,
      projectHeight: projectHeight,
      compositionNodes: nodes,
      audioNodes: audioNodes,
      baseClipIds: baseClipIds ?? _state.baseClipIds,
      baseClipId: baseClipId,
      selectedClipId: selectedClipId,
      baseAudioGain: baseAudioGain,
      baseAudioMuted: baseAudioMuted,
      continuityKind: PreviewContinuityKind.differentSource,
    );
    await applyResolvedPayload(payload);
  }

  @override
  Future<void> play() async {
    await syncTransport(
      positionSeconds: _state.positionSeconds,
      isPlaying: true,
      force: true,
    );
  }

  @override
  Future<void> pause() async {
    await syncTransport(
      positionSeconds: _state.positionSeconds,
      isPlaying: false,
      force: true,
    );
  }

  @override
  Future<void> seek(double seconds) async {
    await syncTransport(
      positionSeconds: seconds,
      isPlaying: _state.isPlaying,
      force: true,
    );
  }

  @override
  Future<void> scrubBegin(double seconds) async {
    final nextRevision = _state.transportRevision + 1;
    _state = _state.copyWith(
      positionSeconds: seconds,
      transportRevision: nextRevision,
    );
    notifyListeners();
    await FusionPreviewSessionBridge.dispatchPreviewCommand(
      projectId: projectId,
      transportRevision: nextRevision,
      command: PreviewTransportCommand(
        kind: PreviewTransportCommandKind.scrubBegin,
        positionSeconds: seconds,
        isPlaying: false,
      ),
    );
  }

  @override
  Future<void> scrubUpdate(double seconds) async {
    final nextRevision = _state.transportRevision + 1;
    _state = _state.copyWith(
      positionSeconds: seconds,
      isPlaying: false,
      transportRevision: nextRevision,
    );
    notifyListeners();
    await FusionPreviewSessionBridge.dispatchPreviewCommand(
      projectId: projectId,
      transportRevision: nextRevision,
      command: PreviewTransportCommand(
        kind: PreviewTransportCommandKind.scrubUpdate,
        positionSeconds: seconds,
        isPlaying: false,
      ),
    );
  }

  @override
  Future<void> scrubEnd(double seconds, {required bool isPlaying}) async {
    final nextRevision = _state.transportRevision + 1;
    _state = _state.copyWith(
      positionSeconds: seconds,
      isPlaying: isPlaying,
      transportRevision: nextRevision,
    );
    notifyListeners();
    await FusionPreviewSessionBridge.dispatchPreviewCommand(
      projectId: projectId,
      transportRevision: nextRevision,
      command: PreviewTransportCommand(
        kind: PreviewTransportCommandKind.scrubEnd,
        positionSeconds: seconds,
        isPlaying: isPlaying,
      ),
    );
  }

  @override
  Widget buildView({BoxFit fit = BoxFit.cover}) {
    return FusionPreviewSurface(projectId: projectId);
  }

  @override
  Future<void> disposeBackend() async {
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
  }

  Future<void> _subscribeToRuntimeEvents() async {
    await _eventsSubscription?.cancel();
    _eventsSubscription = FusionPreviewSessionBridge.watchPreviewEvents(
      projectId,
    ).listen(handleRuntimeEvent);
  }

  void handleRuntimeEvent(PreviewRuntimeEvent event) {
    _state = _state.copyWith(
      positionSeconds: event.positionSeconds,
      isPlaying: event.isPlaying,
      transportRevision: event.transportRevision,
      isBuffering: event.isBuffering,
      isFrameReady: event.frameReady,
      frameDropCount: event.frameDropCount,
      audioDropCount: event.audioDropCount,
      bufferUnderrunCount: event.bufferUnderrunCount,
      previewLatencyMillis: event.previewLatencyMillis,
      seekLatencyMillis: event.seekLatencyMillis,
    );
    notifyListeners();
  }
}
