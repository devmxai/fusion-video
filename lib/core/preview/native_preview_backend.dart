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
  DateTime? _lastTransportPushAt;

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
  Future<void> syncTransport({
    required double positionSeconds,
    required bool isPlaying,
    bool force = false,
  }) async {
    final targetSeconds = positionSeconds < 0 ? 0.0 : positionSeconds;
    final nextState = _state.copyWith(
      positionSeconds: targetSeconds,
      isPlaying: isPlaying,
    );
    final now = DateTime.now();
    final timeSinceLastPush = _lastTransportPushAt == null
        ? const Duration(days: 1)
        : now.difference(_lastTransportPushAt!);
    final shouldPush = force ||
        nextState.isPlaying != _state.isPlaying ||
        (!_state.isPlaying &&
            (nextState.positionSeconds - _state.positionSeconds).abs() >
                0.001) ||
        (nextState.isPlaying &&
            ((nextState.positionSeconds - _state.positionSeconds).abs() >
                    0.12 ||
                timeSinceLastPush >= const Duration(milliseconds: 220)));

    _state = nextState;
    notifyListeners();

    if (shouldPush) {
      _lastTransportPushAt = now;
      await _pushState();
    }
  }

  @override
  Future<void> attachSource(
    PreviewSource? source, {
    bool autoplay = false,
  }) async {
    _state = PreviewBackendState(
      source: source,
      isReady: source != null,
      isPlaying: autoplay,
      durationSeconds: source?.effectiveDurationSeconds ?? 0,
      contentSize: (source?.width != null && source?.height != null)
          ? Size(source!.width!.toDouble(), source.height!.toDouble())
          : null,
    );
    notifyListeners();
    _lastTransportPushAt = null;
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
  Widget buildView({BoxFit fit = BoxFit.cover}) {
    return FusionPreviewSurface(projectId: projectId);
  }

  Future<void> _pushState() {
    return FusionPreviewSessionBridge.updatePreview(
      projectId: projectId,
      positionSeconds: _state.positionSeconds,
      isPlaying: _state.isPlaying,
      sourcePath: _state.source?.localPath,
      sourceKind: switch (_state.source?.kind) {
        PreviewSourceKind.video => 'video',
        PreviewSourceKind.image => 'image',
        null => null,
      },
      sourceStartSeconds: _state.source?.sourceStartSeconds,
      sourceEndSeconds: _state.source?.sourceEndSeconds,
    );
  }

  @override
  Future<void> disposeBackend() async {}
}
