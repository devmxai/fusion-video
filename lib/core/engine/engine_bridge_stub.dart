import 'engine_contract.dart';
import 'engine_runtime_simulation.dart';

class FusionVideoEngineStub implements FusionVideoEngineBridge {
  final Map<int, SimulatedProjectRuntime> _projects = {};
  final Map<int, List<EngineTimelineTrackSnapshot>> _timelineProjects = {};
  final Map<int, Map<String, EngineAssetDescriptor>> _assetProjects = {};
  int _nextProjectId = 1;
  int _nextEditId = 1;

  @override
  Future<void> initialize() async {}

  @override
  Future<EngineProjectHandle> createProject(EngineProjectConfig config) async {
    final id = _nextProjectId++;
    _projects[id] = SimulatedProjectRuntime(config);
    _timelineProjects[id] = _buildDefaultTimeline();
    _assetProjects[id] = <String, EngineAssetDescriptor>{};
    return EngineProjectHandle(id);
  }

  SimulatedProjectRuntime _runtimeFor(EngineProjectHandle handle) {
    final runtime = _projects[handle.id];
    if (runtime == null) {
      throw StateError('Unknown engine project: ${handle.id}');
    }
    return runtime;
  }

  @override
  Future<void> disposeProject(EngineProjectHandle handle) async {
    final runtime = _projects.remove(handle.id);
    runtime?.dispose();
    _timelineProjects.remove(handle.id);
    _assetProjects.remove(handle.id);
  }

  @override
  Future<void> importAsset(
    EngineProjectHandle handle,
    EngineAssetDescriptor asset,
  ) async {
    final assets = _assetProjects[handle.id];
    if (assets == null) {
      throw StateError('Unknown engine project: ${handle.id}');
    }
    assets[asset.id] = asset;
  }

  @override
  Future<void> insertClip(
    EngineProjectHandle handle,
    EngineInsertClipRequest request,
  ) async {
    final current = List<EngineTimelineTrackSnapshot>.from(
      _timelineProjects[handle.id] ?? const [],
    );
    final existingIndex =
        current.indexWhere((track) => track.kind == request.trackKind);

    if (existingIndex >= 0) {
      final existing = current[existingIndex];
      current[existingIndex] = EngineTimelineTrackSnapshot(
        kind: existing.kind,
        clips: [
          ...existing.clips,
          EngineTimelineClipSnapshot(
            id: request.clipId,
            durationSeconds: request.durationSeconds,
            isMedia: request.isMedia,
            assetId: request.assetId,
            sourceOffsetSeconds: 0,
            audioGain: 1.0,
            isMuted: false,
          ),
        ],
      );
    } else {
      current.add(
        EngineTimelineTrackSnapshot(
          kind: request.trackKind,
          clips: [
            EngineTimelineClipSnapshot(
              id: request.clipId,
              durationSeconds: request.durationSeconds,
              isMedia: request.isMedia,
              assetId: request.assetId,
              sourceOffsetSeconds: 0,
              audioGain: 1.0,
              isMuted: false,
            ),
          ],
        ),
      );
      current.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    }

    _timelineProjects[handle.id] = current;
  }

  @override
  Future<void> play(EngineProjectHandle handle) async {
    _runtimeFor(handle).play();
  }

  @override
  Future<void> pause(EngineProjectHandle handle) async {
    _runtimeFor(handle).pause();
  }

  @override
  Future<void> seek(
    EngineProjectHandle handle,
    EngineTimelinePosition position,
  ) async {
    _runtimeFor(handle).seek(position.seconds);
  }

  @override
  Future<void> splitSelectedClip(
    EngineProjectHandle handle,
    String clipId,
    EngineTimelinePosition position,
  ) async {
    final location = _findClip(handle.id, clipId);
    if (location == null || !location.clip.isMedia) {
      return;
    }

    const edgePadding = 0.05;
    if (location.endSeconds - location.startSeconds <= edgePadding * 2) {
      return;
    }

    final splitAt = position.seconds.clamp(
      location.startSeconds + edgePadding,
      location.endSeconds - edgePadding,
    );
    final leftDuration = splitAt - location.startSeconds;
    final rightDuration = location.endSeconds - splitAt;
    final stamp = _nextEditId++;
    final splitGroupId = 'bridge_$stamp';

    final nextClips =
        List<EngineTimelineClipSnapshot>.from(location.track.clips)
          ..removeAt(location.clipIndex)
          ..insertAll(location.clipIndex, [
            EngineTimelineClipSnapshot(
              id: '${location.clip.id}_a_$stamp',
              durationSeconds: leftDuration,
              isMedia: true,
              assetId: location.clip.assetId,
              sourceOffsetSeconds: location.clip.sourceOffsetSeconds ?? 0,
              splitGroupId: splitGroupId,
              audioGain: location.clip.audioGain,
              isMuted: location.clip.isMuted,
            ),
            EngineTimelineClipSnapshot(
              id: '${location.clip.id}_b_$stamp',
              durationSeconds: rightDuration,
              isMedia: true,
              assetId: location.clip.assetId,
              sourceOffsetSeconds:
                  (location.clip.sourceOffsetSeconds ?? 0) + leftDuration,
              splitGroupId: splitGroupId,
              audioGain: location.clip.audioGain,
              isMuted: location.clip.isMuted,
            ),
          ]);

    _replaceTrack(
      handle.id,
      location.trackIndex,
      EngineTimelineTrackSnapshot(kind: location.track.kind, clips: nextClips),
    );
  }

  @override
  Future<void> trimClipLeft(
    EngineProjectHandle handle,
    String clipId,
    EngineTimelinePosition position,
  ) async {
    final location = _findClip(handle.id, clipId);
    if (location == null || !location.clip.isMedia) {
      return;
    }

    const minDuration = 0.2;
    final newStart = position.seconds.clamp(
      location.startSeconds,
      location.endSeconds - minDuration,
    );
    final delta = newStart - location.startSeconds;
    if (delta <= 0.01) {
      return;
    }

    final nextClips =
        List<EngineTimelineClipSnapshot>.from(location.track.clips);
    nextClips[location.clipIndex] = EngineTimelineClipSnapshot(
      id: location.clip.id,
      durationSeconds: location.clip.durationSeconds - delta,
      isMedia: location.clip.isMedia,
      assetId: location.clip.assetId,
      sourceOffsetSeconds: (location.clip.sourceOffsetSeconds ?? 0) + delta,
      splitGroupId: location.clip.splitGroupId,
      audioGain: location.clip.audioGain,
      isMuted: location.clip.isMuted,
    );
    _replaceTrack(
      handle.id,
      location.trackIndex,
      EngineTimelineTrackSnapshot(kind: location.track.kind, clips: nextClips),
    );
  }

  @override
  Future<void> trimClipRight(
    EngineProjectHandle handle,
    String clipId,
    EngineTimelinePosition position,
  ) async {
    final location = _findClip(handle.id, clipId);
    if (location == null || !location.clip.isMedia) {
      return;
    }

    const minDuration = 0.2;
    final newEnd = position.seconds.clamp(
      location.startSeconds + minDuration,
      location.endSeconds,
    );
    final newDuration = newEnd - location.startSeconds;
    if ((newDuration - location.clip.durationSeconds).abs() <= 0.01 ||
        newDuration >= location.clip.durationSeconds) {
      return;
    }

    final nextClips =
        List<EngineTimelineClipSnapshot>.from(location.track.clips);
    nextClips[location.clipIndex] = EngineTimelineClipSnapshot(
      id: location.clip.id,
      durationSeconds: newDuration,
      isMedia: location.clip.isMedia,
      assetId: location.clip.assetId,
      sourceOffsetSeconds: location.clip.sourceOffsetSeconds,
      splitGroupId: location.clip.splitGroupId,
      audioGain: location.clip.audioGain,
      isMuted: location.clip.isMuted,
    );
    _replaceTrack(
      handle.id,
      location.trackIndex,
      EngineTimelineTrackSnapshot(kind: location.track.kind, clips: nextClips),
    );
  }

  @override
  Future<void> deleteClip(
    EngineProjectHandle handle,
    String clipId,
  ) async {
    final location = _findClip(handle.id, clipId);
    if (location == null) {
      return;
    }

    final nextClips =
        List<EngineTimelineClipSnapshot>.from(location.track.clips)
          ..removeAt(location.clipIndex);
    _replaceTrack(
      handle.id,
      location.trackIndex,
      EngineTimelineTrackSnapshot(kind: location.track.kind, clips: nextClips),
    );
  }

  @override
  Future<void> duplicateClip(
    EngineProjectHandle handle,
    String clipId,
  ) async {
    final location = _findClip(handle.id, clipId);
    if (location == null) {
      return;
    }

    final stamp = _nextEditId++;
    final duplicate = EngineTimelineClipSnapshot(
      id: '${location.clip.id}_copy_$stamp',
      durationSeconds: location.clip.durationSeconds,
      isMedia: location.clip.isMedia,
      assetId: location.clip.assetId,
      sourceOffsetSeconds: location.clip.sourceOffsetSeconds,
      splitGroupId: null,
      audioGain: location.clip.audioGain,
      isMuted: location.clip.isMuted,
    );

    final nextClips =
        List<EngineTimelineClipSnapshot>.from(location.track.clips)
          ..insert(location.clipIndex + 1, duplicate);
    _replaceTrack(
      handle.id,
      location.trackIndex,
      EngineTimelineTrackSnapshot(kind: location.track.kind, clips: nextClips),
    );
  }

  @override
  Future<void> setClipGain(
    EngineProjectHandle handle,
    String clipId,
    double gain,
  ) async {
    final location = _findClip(handle.id, clipId);
    if (location == null || !location.clip.isMedia) {
      return;
    }

    final nextClips =
        List<EngineTimelineClipSnapshot>.from(location.track.clips);
    nextClips[location.clipIndex] = EngineTimelineClipSnapshot(
      id: location.clip.id,
      durationSeconds: location.clip.durationSeconds,
      isMedia: location.clip.isMedia,
      assetId: location.clip.assetId,
      sourceOffsetSeconds: location.clip.sourceOffsetSeconds,
      splitGroupId: location.clip.splitGroupId,
      audioGain: gain.clamp(0.0, 1.0),
      isMuted: location.clip.isMuted,
    );
    _replaceTrack(
      handle.id,
      location.trackIndex,
      EngineTimelineTrackSnapshot(kind: location.track.kind, clips: nextClips),
    );
  }

  @override
  Future<void> setClipMuted(
    EngineProjectHandle handle,
    String clipId,
    bool muted,
  ) async {
    final location = _findClip(handle.id, clipId);
    if (location == null || !location.clip.isMedia) {
      return;
    }

    final nextClips =
        List<EngineTimelineClipSnapshot>.from(location.track.clips);
    nextClips[location.clipIndex] = EngineTimelineClipSnapshot(
      id: location.clip.id,
      durationSeconds: location.clip.durationSeconds,
      isMedia: location.clip.isMedia,
      assetId: location.clip.assetId,
      sourceOffsetSeconds: location.clip.sourceOffsetSeconds,
      splitGroupId: location.clip.splitGroupId,
      audioGain: location.clip.audioGain,
      isMuted: muted,
    );
    _replaceTrack(
      handle.id,
      location.trackIndex,
      EngineTimelineTrackSnapshot(kind: location.track.kind, clips: nextClips),
    );
  }

  @override
  Future<List<EngineTimelineTrackSnapshot>> fetchTimelineTracks(
    EngineProjectHandle handle,
  ) async {
    return List<EngineTimelineTrackSnapshot>.from(
      _timelineProjects[handle.id] ?? const [],
    );
  }

  @override
  Future<List<EngineCompositionNodeSnapshot>> fetchCompositionNodes(
    EngineProjectHandle handle,
    EngineTimelinePosition position,
  ) async {
    final tracks = _timelineProjects[handle.id] ?? const [];
    final assets =
        _assetProjects[handle.id] ?? const <String, EngineAssetDescriptor>{};
    final nodes = <EngineCompositionNodeSnapshot>[];

    for (final track in tracks) {
      if (track.kind == EngineTrackKind.audio ||
          track.kind == EngineTrackKind.effect) {
        continue;
      }
      var elapsed = 0.0;
      for (final clip in track.clips) {
        final start = elapsed;
        final end = start + clip.durationSeconds;
        elapsed = end;
        if (!clip.isMedia) {
          continue;
        }
        if (position.seconds < start || position.seconds > end + 0.0001) {
          continue;
        }
        final assetId = clip.assetId;
        if (assetId == null) {
          continue;
        }
        final asset = assets[assetId];
        if (asset == null) {
          continue;
        }
        final sourceStartSeconds = clip.sourceOffsetSeconds ?? 0.0;
        final sourcePositionSeconds = sourceStartSeconds +
            (position.seconds - start).clamp(0.0, clip.durationSeconds);
        nodes.add(
          EngineCompositionNodeSnapshot(
            clipId: clip.id,
            assetId: assetId,
            trackKind: track.kind,
            assetUri: asset.uri,
            displayLabel: asset.label,
            clipStartSeconds: start,
            clipEndSeconds: end,
            clipDurationSeconds: clip.durationSeconds,
            sourceStartSeconds: sourceStartSeconds,
            sourceEndSeconds: sourceStartSeconds + clip.durationSeconds,
            sourcePositionSeconds: sourcePositionSeconds,
            transform: _defaultTransformFor(asset.kind),
          ),
        );
      }
    }

    nodes.sort((a, b) => a.transform.zIndex.compareTo(b.transform.zIndex));
    return nodes;
  }

  @override
  Future<List<EngineAudioNodeSnapshot>> fetchAudioNodes(
    EngineProjectHandle handle,
    EngineTimelinePosition position,
  ) async {
    final tracks = _timelineProjects[handle.id] ?? const [];
    final assets =
        _assetProjects[handle.id] ?? const <String, EngineAssetDescriptor>{};
    final nodes = <EngineAudioNodeSnapshot>[];

    for (final track in tracks) {
      if (track.kind != EngineTrackKind.audio &&
          track.kind != EngineTrackKind.video) {
        continue;
      }
      var elapsed = 0.0;
      for (final clip in track.clips) {
        final start = elapsed;
        final end = start + clip.durationSeconds;
        elapsed = end;
        if (!clip.isMedia) {
          continue;
        }
        if (position.seconds < start || position.seconds > end + 0.0001) {
          continue;
        }
        final assetId = clip.assetId;
        if (assetId == null) {
          continue;
        }
        final asset = assets[assetId];
        if (asset == null) {
          continue;
        }
        final sourceStartSeconds = clip.sourceOffsetSeconds ?? 0.0;
        final sourcePositionSeconds = sourceStartSeconds +
            (position.seconds - start).clamp(0.0, clip.durationSeconds);
        nodes.add(
          EngineAudioNodeSnapshot(
            clipId: clip.id,
            assetId: assetId,
            trackKind: track.kind,
            assetUri: asset.uri,
            displayLabel: asset.label,
            clipStartSeconds: start,
            clipEndSeconds: end,
            clipDurationSeconds: clip.durationSeconds,
            sourceStartSeconds: sourceStartSeconds,
            sourceEndSeconds: sourceStartSeconds + clip.durationSeconds,
            sourcePositionSeconds: sourcePositionSeconds,
            gain: clip.audioGain,
            isMuted: clip.isMuted,
          ),
        );
      }
    }

    return nodes;
  }

  @override
  Stream<EngineStatusSnapshot> watchStatus(EngineProjectHandle handle) {
    return _runtimeFor(handle).stream;
  }

  List<EngineTimelineTrackSnapshot> _buildDefaultTimeline() => const [];

  _StubClipLocation? _findClip(int handleId, String clipId) {
    final tracks = _timelineProjects[handleId];
    if (tracks == null) {
      return null;
    }

    for (var trackIndex = 0; trackIndex < tracks.length; trackIndex++) {
      var elapsed = 0.0;
      final track = tracks[trackIndex];
      for (var clipIndex = 0; clipIndex < track.clips.length; clipIndex++) {
        final clip = track.clips[clipIndex];
        final start = elapsed;
        final end = start + clip.durationSeconds;
        if (clip.id == clipId) {
          return _StubClipLocation(
            trackIndex: trackIndex,
            clipIndex: clipIndex,
            track: track,
            clip: clip,
            startSeconds: start,
            endSeconds: end,
          );
        }
        elapsed = end;
      }
    }

    return null;
  }

  void _replaceTrack(
    int handleId,
    int trackIndex,
    EngineTimelineTrackSnapshot nextTrack,
  ) {
    final current = List<EngineTimelineTrackSnapshot>.from(
      _timelineProjects[handleId] ?? const [],
    );
    current[trackIndex] = nextTrack;
    _timelineProjects[handleId] = current;
  }

  EngineVisualTransformSnapshot _defaultTransformFor(EngineTrackKind kind) {
    switch (kind) {
      case EngineTrackKind.video:
        return const EngineVisualTransformSnapshot(
          x: 0,
          y: 0,
          width: 1080,
          height: 1920,
          opacity: 1,
          rotationDegrees: 0,
          zIndex: 0,
        );
      case EngineTrackKind.image:
        return const EngineVisualTransformSnapshot(
          x: 0,
          y: 0,
          width: 1080,
          height: 1920,
          opacity: 1,
          rotationDegrees: 0,
          zIndex: 10,
        );
      case EngineTrackKind.text:
        return const EngineVisualTransformSnapshot(
          x: 120,
          y: 1480,
          width: 840,
          height: 220,
          opacity: 1,
          rotationDegrees: 0,
          zIndex: 20,
        );
      case EngineTrackKind.lipSync:
        return const EngineVisualTransformSnapshot(
          x: 250,
          y: 1260,
          width: 580,
          height: 220,
          opacity: 1,
          rotationDegrees: 0,
          zIndex: 30,
        );
      case EngineTrackKind.audio:
      case EngineTrackKind.effect:
        return const EngineVisualTransformSnapshot(
          x: 0,
          y: 0,
          width: 0,
          height: 0,
          opacity: 1,
          rotationDegrees: 0,
          zIndex: 0,
        );
    }
  }
}

class _StubClipLocation {
  const _StubClipLocation({
    required this.trackIndex,
    required this.clipIndex,
    required this.track,
    required this.clip,
    required this.startSeconds,
    required this.endSeconds,
  });

  final int trackIndex;
  final int clipIndex;
  final EngineTimelineTrackSnapshot track;
  final EngineTimelineClipSnapshot clip;
  final double startSeconds;
  final double endSeconds;
}
