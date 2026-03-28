import 'engine_contract.dart';
import 'engine_runtime_simulation.dart';

class FusionVideoEngineStub implements FusionVideoEngineBridge {
  final Map<int, SimulatedProjectRuntime> _projects = {};
  final Map<int, List<EngineTimelineTrackSnapshot>> _timelineProjects = {};
  int _nextProjectId = 1;
  int _nextEditId = 1;

  @override
  Future<void> initialize() async {}

  @override
  Future<EngineProjectHandle> createProject(EngineProjectConfig config) async {
    final id = _nextProjectId++;
    _projects[id] = SimulatedProjectRuntime(config);
    _timelineProjects[id] = _buildDefaultTimeline();
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
  }

  @override
  Future<void> importAsset(
    EngineProjectHandle handle,
    EngineAssetDescriptor asset,
  ) async {}

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
              splitGroupId: splitGroupId,
            ),
            EngineTimelineClipSnapshot(
              id: '${location.clip.id}_b_$stamp',
              durationSeconds: rightDuration,
              isMedia: true,
              splitGroupId: splitGroupId,
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
      splitGroupId: location.clip.splitGroupId,
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
      splitGroupId: location.clip.splitGroupId,
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
      splitGroupId: null,
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
  Future<List<EngineTimelineTrackSnapshot>> fetchTimelineTracks(
    EngineProjectHandle handle,
  ) async {
    return List<EngineTimelineTrackSnapshot>.from(
      _timelineProjects[handle.id] ?? const [],
    );
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
