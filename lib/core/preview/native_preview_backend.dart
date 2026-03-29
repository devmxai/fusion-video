import 'package:flutter/material.dart';

import 'fusion_preview_surface.dart';
import 'preview_backend.dart';
import 'preview_session_bridge.dart';

class NativePreviewBackend extends FusionPreviewBackend {
  NativePreviewBackend({
    required this.projectId,
  });

  int projectId;
  PreviewBackendState _state = const PreviewBackendState();

  @override
  PreviewBackendState get state => _state;

  @override
  Future<void> bindProject(int projectId) async {
    if (this.projectId == projectId) {
      return;
    }
    this.projectId = projectId;
    await _pushState();
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
    await _pushState();
  }

  @override
  Future<void> syncTransport({
    required double positionSeconds,
    required bool isPlaying,
    bool force = false,
  }) async {
    final targetSeconds = positionSeconds < 0 ? 0.0 : positionSeconds;
    final baseState = _state.copyWith(
      positionSeconds: targetSeconds,
      isPlaying: isPlaying,
    );
    final shouldPush = force ||
        baseState.isPlaying != _state.isPlaying ||
        (!baseState.isPlaying &&
            (baseState.positionSeconds - _state.positionSeconds).abs() > 0.001);
    final nextState = baseState.copyWith(
      transportRevision: _state.transportRevision + (shouldPush ? 1 : 0),
    );

    _state = nextState;
    notifyListeners();
    if (!shouldPush) {
      return;
    }
    await _pushState();
  }

  @override
  Future<void> attachSource(
    PreviewSource? source, {
    bool autoplay = false,
    PreviewSource? upcomingSource,
  }) async {
    final shouldKeepPlaying =
        source != null && (autoplay || (_state.isReady && _state.isPlaying));
    _state = _state.copyWith(
      source: source,
      clearSource: source == null,
      upcomingSource: upcomingSource,
      clearUpcomingSource: upcomingSource == null,
      isReady: source != null,
      isPlaying: source == null ? false : shouldKeepPlaying,
      durationSeconds: source?.effectiveDurationSeconds ?? 0,
      contentSize: (source?.width != null && source?.height != null)
          ? Size(source!.width!.toDouble(), source.height!.toDouble())
          : null,
      clearContentSize: source == null,
    );
    notifyListeners();
    await _pushState();
  }

  @override
  Future<void> updateSource(
    PreviewSource? source, {
    PreviewSource? upcomingSource,
  }) async {
    _state = _state.copyWith(
      source: source,
      clearSource: source == null,
      upcomingSource: upcomingSource,
      clearUpcomingSource: upcomingSource == null,
      isReady: source != null,
      durationSeconds: source?.effectiveDurationSeconds ?? 0,
      contentSize: (source?.width != null && source?.height != null)
          ? Size(source!.width!.toDouble(), source.height!.toDouble())
          : null,
      clearContentSize: source == null,
    );
    notifyListeners();
    await _pushState();
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
    _state = _state.copyWith(
      compositionNodes: nodes,
      audioNodes: audioNodes,
      projectWidth: projectWidth,
      projectHeight: projectHeight,
      baseClipId: baseClipId,
      clearBaseClipId: baseClipId == null,
      baseClipIds: baseClipIds,
      selectedClipId: selectedClipId,
      clearSelectedClipId: selectedClipId == null,
      baseAudioGain: baseAudioGain,
      baseAudioMuted: baseAudioMuted,
    );
    notifyListeners();
    await _pushState();
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
    await syncTransport(
      positionSeconds: seconds,
      isPlaying: false,
      force: true,
    );
  }

  @override
  Future<void> scrubUpdate(double seconds) async {
    await syncTransport(
      positionSeconds: seconds,
      isPlaying: false,
      force: true,
    );
  }

  @override
  Future<void> scrubEnd(double seconds, {required bool isPlaying}) async {
    await syncTransport(
      positionSeconds: seconds,
      isPlaying: isPlaying,
      force: true,
    );
  }

  @override
  Widget buildView({BoxFit fit = BoxFit.cover}) {
    return FusionPreviewSurface(projectId: projectId);
  }

  Future<void> _pushState() {
    return FusionPreviewSessionBridge.updatePreview(
      projectId: projectId,
      positionSeconds: _state.positionSeconds,
      isPlaying: _state.isPlaying,
      transportRevision: _state.transportRevision,
      sourceId: _state.source?.effectiveAttachmentId,
      sourcePath: _state.source?.localPath,
      sourceKind: switch (_state.source?.kind) {
        PreviewSourceKind.video => 'video',
        PreviewSourceKind.image => 'image',
        null => null,
      },
      upcomingSourceId: _state.upcomingSource?.effectiveAttachmentId,
      upcomingSourcePath: _state.upcomingSource?.localPath,
      upcomingSourceKind: switch (_state.upcomingSource?.kind) {
        PreviewSourceKind.video => 'video',
        PreviewSourceKind.image => 'image',
        null => null,
      },
      clipStartSeconds: _state.source?.clipStartSeconds,
      clipEndSeconds: _state.source?.clipEndSeconds,
      sourceStartSeconds: _state.source?.sourceStartSeconds,
      sourceEndSeconds: _state.source?.sourceEndSeconds,
      upcomingSourceStartSeconds: _state.upcomingSource?.sourceStartSeconds,
      upcomingSourceEndSeconds: _state.upcomingSource?.sourceEndSeconds,
      projectWidth: _state.projectWidth,
      projectHeight: _state.projectHeight,
      baseClipId: _state.baseClipId,
      baseClipIds: _state.baseClipIds,
      selectedClipId: _state.selectedClipId,
      baseAudioGain: _state.baseAudioGain,
      baseAudioMuted: _state.baseAudioMuted,
      sceneNodes: _state.compositionNodes.map((node) => node.toMap()).toList(),
      audioNodes: _state.audioNodes.map((node) => node.toMap()).toList(),
    );
  }

  @override
  Future<void> disposeBackend() async {}
}
