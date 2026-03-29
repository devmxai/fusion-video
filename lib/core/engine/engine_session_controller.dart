import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../features/editor/presentation/models/timeline_mock_models.dart';
import 'engine_bridge_factory.dart';
import 'engine_contract.dart';

class FusionVideoEngineSessionController extends ChangeNotifier {
  FusionVideoEngineSessionController({
    FusionVideoEngineBridge? bridge,
    required EngineProjectConfig config,
    List<TimelineTrackData>? initialTracks,
    String? initialSelectedClipId,
  })  : _bridge = bridge ?? createFusionVideoEngineBridge(),
        _config = config,
        _tracks = List<TimelineTrackData>.from(
          initialTracks ?? const <TimelineTrackData>[],
        ),
        _selectedClipId = initialSelectedClipId;

  final FusionVideoEngineBridge _bridge;
  final EngineProjectConfig _config;
  final Map<String, EngineAssetDescriptor> _assetRegistry = {};

  EngineProjectHandle? _projectHandle;
  StreamSubscription<EngineStatusSnapshot>? _statusSubscription;
  List<TimelineTrackData> _tracks;
  String? _selectedClipId;

  bool _ready = false;
  EngineStatusSnapshot _status = const EngineStatusSnapshot(
    playbackState: EnginePlaybackState.stopped,
    position: EngineTimelinePosition(seconds: 0, frame: 0),
    isBuffering: false,
  );

  bool get isReady => _ready;
  bool get isPlaying => _status.playbackState == EnginePlaybackState.playing;
  bool get isBuffering => _status.isBuffering;
  double get currentSeconds => _status.position.seconds;
  EngineStatusSnapshot get status => _status;
  EngineProjectHandle? get projectHandle => _projectHandle;
  double get durationSeconds {
    final longestTrack = _tracks.fold<double>(
      0,
      (maxDuration, track) => math.max(
        maxDuration,
        track.clips.fold<double>(
          0,
          (sum, clip) => sum + clip.duration,
        ),
      ),
    );
    return math.max(_config.durationSeconds, longestTrack);
  }

  int get projectWidth => _config.width;
  int get projectHeight => _config.height;

  List<TimelineTrackData> get tracks => List.unmodifiable(_tracks);
  String? get selectedClipId => _selectedClipId;
  Map<String, EngineAssetDescriptor> get assetRegistry =>
      Map.unmodifiable(_assetRegistry);
  EngineAssetDescriptor? assetForId(String assetId) => _assetRegistry[assetId];

  EngineVisualBinding? visualBindingForClipId(
    String clipId, {
    double? projectSeconds,
  }) {
    final location = _findClip(clipId);
    if (location == null) {
      return null;
    }
    final assetId = location.clip.assetId;
    if (assetId == null) {
      return null;
    }
    final asset = _assetRegistry[assetId];
    if (asset == null ||
        (asset.kind != EngineTrackKind.video &&
            asset.kind != EngineTrackKind.image)) {
      return null;
    }

    final seconds = projectSeconds ?? currentSeconds;
    final timeWithinClip =
        (seconds - location.start).clamp(0.0, location.clip.duration);
    return EngineVisualBinding(
      clipId: location.clip.id,
      asset: asset,
      clipStartSeconds: location.start,
      clipEndSeconds: location.end,
      clipDurationSeconds: location.clip.duration,
      sourceStartSeconds: location.clip.sourceOffsetSeconds ?? 0,
      sourceEndSeconds:
          (location.clip.sourceOffsetSeconds ?? 0) + location.clip.duration,
      sourcePositionSeconds:
          (location.clip.sourceOffsetSeconds ?? 0) + timeWithinClip,
    );
  }

  EngineAssetDescriptor? assetForClipId(String clipId) {
    final location = _findClip(clipId);
    final assetId = location?.clip.assetId;
    if (assetId == null) {
      return null;
    }
    return _assetRegistry[assetId];
  }

  EngineAssetDescriptor? activeVisualAssetAt(double seconds) {
    return activeVisualBindingAt(seconds)?.asset;
  }

  Future<List<EngineCompositionNodeSnapshot>> compositionAt(
    double seconds,
  ) async {
    final handle = _projectHandle;
    if (handle == null) {
      return const <EngineCompositionNodeSnapshot>[];
    }

    final clamped = seconds.clamp(0.0, durationSeconds);
    return _bridge.fetchCompositionNodes(
      handle,
      EngineTimelinePosition(
        seconds: clamped,
        frame: (clamped * _config.fps).round(),
      ),
    );
  }

  Future<EngineCompositionNodeSnapshot?> activeCompositionNodeAt(
    double seconds,
  ) async {
    final nodes = await compositionAt(seconds);
    if (nodes.isEmpty) {
      return null;
    }
    return nodes.last;
  }

  Future<EngineCompositionNodeSnapshot?> compositionNodeForClipId(
    String clipId, {
    double? projectSeconds,
  }) async {
    final location = _findClip(clipId);
    if (location == null) {
      return null;
    }

    final targetSeconds = (projectSeconds ?? currentSeconds).clamp(
      location.start,
      location.end,
    );
    final nodes = await compositionAt(targetSeconds);
    for (final node in nodes) {
      if (node.clipId == clipId) {
        return node;
      }
    }
    return null;
  }

  Future<List<EngineAudioNodeSnapshot>> audioNodesAt(double seconds) async {
    final handle = _projectHandle;
    if (handle == null) {
      return const <EngineAudioNodeSnapshot>[];
    }

    final clamped = seconds.clamp(0.0, durationSeconds);
    return _bridge.fetchAudioNodes(
      handle,
      EngineTimelinePosition(
        seconds: clamped,
        frame: (clamped * _config.fps).round(),
      ),
    );
  }

  Future<EngineAudioNodeSnapshot?> activeAudioNodeAt(double seconds) async {
    final nodes = await audioNodesAt(seconds);
    if (nodes.isEmpty) {
      return null;
    }
    return nodes.last;
  }

  EngineVisualBinding? activeVisualBindingAt(double seconds) {
    for (final track in _tracks) {
      if (track.kind != TimelineTrackKind.video &&
          track.kind != TimelineTrackKind.image) {
        continue;
      }
      var elapsed = 0.0;
      for (final clip in track.clips) {
        final start = elapsed;
        final end = start + clip.duration;
        elapsed = end;
        if (clip.type != TimelineClipType.media) {
          continue;
        }
        if (seconds >= start && seconds <= end + 0.0001) {
          final assetId = clip.assetId;
          if (assetId == null) {
            return null;
          }
          final asset = _assetRegistry[assetId];
          if (asset == null) {
            return null;
          }
          final timeWithinClip = (seconds - start).clamp(0.0, clip.duration);
          return EngineVisualBinding(
            clipId: clip.id,
            asset: asset,
            clipStartSeconds: start,
            clipEndSeconds: end,
            clipDurationSeconds: clip.duration,
            sourceStartSeconds: clip.sourceOffsetSeconds ?? 0,
            sourceEndSeconds: (clip.sourceOffsetSeconds ?? 0) + clip.duration,
            sourcePositionSeconds:
                (clip.sourceOffsetSeconds ?? 0) + timeWithinClip,
          );
        }
      }
    }
    return null;
  }

  Future<void> initialize() async {
    if (_ready) {
      return;
    }

    await _bridge.initialize();
    final handle = await _bridge.createProject(_config);
    _projectHandle = handle;
    _tracks = await _loadTracksFromEngine(handle);
    _statusSubscription = _bridge.watchStatus(handle).listen((snapshot) {
      _status = snapshot;
      notifyListeners();
    });
    _ready = true;
    notifyListeners();
  }

  Future<void> play() async {
    final handle = _projectHandle;
    if (handle == null) {
      return;
    }
    await _bridge.play(handle);
  }

  Future<void> pause() async {
    final handle = _projectHandle;
    if (handle == null) {
      return;
    }
    await _bridge.pause(handle);
  }

  Future<void> togglePlayback() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seekSeconds(double seconds) async {
    final handle = _projectHandle;
    if (handle == null) {
      return;
    }

    final clamped = seconds.clamp(0.0, durationSeconds);
    final frame = (clamped * _config.fps).round();
    await _bridge.seek(
      handle,
      EngineTimelinePosition(seconds: clamped, frame: frame),
    );
  }

  void selectClip(String clipId) {
    if (_selectedClipId == clipId) {
      return;
    }
    _selectedClipId = clipId;
    notifyListeners();
  }

  void clearSelectedClip() {
    if (_selectedClipId == null) {
      return;
    }
    _selectedClipId = null;
    notifyListeners();
  }

  Future<void> splitSelectedClip() async {
    return splitSelectedClipAt(currentSeconds);
  }

  Future<void> splitSelectedClipAt(double projectSeconds) async {
    final selectedClipId = _selectedClipId;
    final handle = _projectHandle;
    if (selectedClipId == null || handle == null) {
      return;
    }

    final target = _findClip(selectedClipId);
    if (target == null || target.clip.type != TimelineClipType.media) {
      return;
    }

    final previousTracks = _tracks;
    final previousSelectedClipId = _selectedClipId;
    final updatedTracks = <TimelineTrackData>[];
    var didSplit = false;
    final splitStamp = DateTime.now().microsecondsSinceEpoch.toString();
    final current = projectSeconds.clamp(0.0, durationSeconds).toDouble();
    const edgePadding = 0.05;
    if (current <= target.start + edgePadding ||
        current >= target.end - edgePadding) {
      return;
    }

    for (final track in _tracks) {
      var elapsed = 0.0;
      final nextClips = <TimelineClipData>[];

      for (final clip in track.clips) {
        final start = elapsed;
        final end = start + clip.duration;
        elapsed = end;

        if (!didSplit &&
            clip.id == selectedClipId &&
            clip.type == TimelineClipType.media) {
          if (end - start <= edgePadding * 2) {
            nextClips.add(clip);
            continue;
          }
          final splitAt = current;
          final leftDuration = splitAt - start;
          final rightDuration = end - splitAt;
          final splitGroupId = 'bridge_$splitStamp';

          final leftClip = clip.copyWith(
            id: '${clip.id}_a_$splitStamp',
            duration: leftDuration,
            splitGroupId: splitGroupId,
          );
          final rightClip = clip.copyWith(
            id: '${clip.id}_b_$splitStamp',
            duration: rightDuration,
            splitGroupId: splitGroupId,
          );

          nextClips
            ..add(leftClip)
            ..add(rightClip);
          _selectedClipId = null;
          didSplit = true;
          continue;
        }

        nextClips.add(clip);
      }

      updatedTracks.add(track.copyWith(clips: nextClips));
    }

    if (!didSplit) {
      return;
    }

    _tracks = updatedTracks;
    notifyListeners();

    final bridgeSeconds = current.clamp(0.0, durationSeconds).toDouble();
    try {
      await _bridge.splitSelectedClip(
        handle,
        selectedClipId,
        EngineTimelinePosition(
          seconds: bridgeSeconds,
          frame: (bridgeSeconds * _config.fps).round(),
        ),
      );
      _tracks = await _loadTracksFromEngine(handle);
      _selectedClipId = null;
      notifyListeners();
    } catch (_) {
      _tracks = previousTracks;
      _selectedClipId = previousSelectedClipId;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> trimSelectedClipLeft() async {
    return trimSelectedClipLeftAt(currentSeconds);
  }

  Future<void> trimSelectedClipLeftAt(double projectSeconds) async {
    final selectedClipId = _selectedClipId;
    final handle = _projectHandle;
    if (selectedClipId == null || handle == null) {
      return;
    }

    final result = _findClip(selectedClipId);
    if (result == null || result.clip.type != TimelineClipType.media) {
      return;
    }

    final previousTracks = _tracks;
    const minDuration = 0.2;
    final newStart = projectSeconds.clamp(
      result.start,
      result.end - minDuration,
    );
    final delta = newStart - result.start;
    if (delta <= 0.01) {
      return;
    }

    final updatedTracks = List<TimelineTrackData>.from(_tracks);
    final targetTrack = updatedTracks[result.trackIndex];
    final nextClips = List<TimelineClipData>.from(targetTrack.clips);
    nextClips[result.clipIndex] = result.clip.copyWith(
      duration: result.clip.duration - delta,
      sourceOffsetSeconds: (result.clip.sourceOffsetSeconds ?? 0) + delta,
    );
    updatedTracks[result.trackIndex] = targetTrack.copyWith(clips: nextClips);
    _tracks = updatedTracks;
    notifyListeners();

    try {
      await _bridge.trimClipLeft(
        handle,
        selectedClipId,
        EngineTimelinePosition(
          seconds: newStart,
          frame: (newStart * _config.fps).round(),
        ),
      );
      _tracks = await _loadTracksFromEngine(handle);
      notifyListeners();
    } catch (_) {
      _tracks = previousTracks;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> trimSelectedClipRight() async {
    return trimSelectedClipRightAt(currentSeconds);
  }

  Future<void> trimSelectedClipRightAt(double projectSeconds) async {
    final selectedClipId = _selectedClipId;
    final handle = _projectHandle;
    if (selectedClipId == null || handle == null) {
      return;
    }

    final result = _findClip(selectedClipId);
    if (result == null || result.clip.type != TimelineClipType.media) {
      return;
    }

    final previousTracks = _tracks;
    const minDuration = 0.2;
    final newEnd = projectSeconds.clamp(
      result.start + minDuration,
      result.end,
    );
    final newDuration = newEnd - result.start;
    if ((newDuration - result.clip.duration).abs() <= 0.01 ||
        newDuration >= result.clip.duration) {
      return;
    }

    final updatedTracks = List<TimelineTrackData>.from(_tracks);
    final targetTrack = updatedTracks[result.trackIndex];
    final nextClips = List<TimelineClipData>.from(targetTrack.clips);
    nextClips[result.clipIndex] = result.clip.copyWith(
      duration: newDuration,
    );
    updatedTracks[result.trackIndex] = targetTrack.copyWith(clips: nextClips);
    _tracks = updatedTracks;
    notifyListeners();

    try {
      await _bridge.trimClipRight(
        handle,
        selectedClipId,
        EngineTimelinePosition(
          seconds: newEnd,
          frame: (newEnd * _config.fps).round(),
        ),
      );
      _tracks = await _loadTracksFromEngine(handle);
      notifyListeners();
    } catch (_) {
      _tracks = previousTracks;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteSelectedClip() async {
    final selectedClipId = _selectedClipId;
    final handle = _projectHandle;
    if (selectedClipId == null || handle == null) {
      return;
    }

    final result = _findClip(selectedClipId);
    if (result == null) {
      return;
    }

    final localTrackClips = _tracks[result.trackIndex].clips;
    String? nextSelectedClipId;
    if (localTrackClips.length > 1) {
      final nextIndex = (result.clipIndex).clamp(0, localTrackClips.length - 2);
      nextSelectedClipId = localTrackClips[
              nextIndex == result.clipIndex ? nextIndex + 1 : nextIndex]
          .id;
    }

    await _bridge.deleteClip(handle, selectedClipId);
    _tracks = await _loadTracksFromEngine(handle);
    _selectedClipId =
        nextSelectedClipId != null && _containsClipId(nextSelectedClipId)
            ? nextSelectedClipId
            : _firstAvailableClipId();
    notifyListeners();
  }

  Future<void> duplicateSelectedClip() async {
    final selectedClipId = _selectedClipId;
    final handle = _projectHandle;
    if (selectedClipId == null || handle == null) {
      return;
    }

    final result = _findClip(selectedClipId);
    if (result == null) {
      return;
    }

    final duplicateId =
        '${result.clip.id}_copy_${DateTime.now().microsecondsSinceEpoch}';
    await _bridge.duplicateClip(handle, selectedClipId);
    _tracks = await _loadTracksFromEngine(handle);
    _selectedClipId =
        _findNewestClipIdByPrefix('${selectedClipId}_copy_') ?? duplicateId;
    notifyListeners();
  }

  Future<void> reorderClipInTrack(
    String clipId, {
    required int insertionIndex,
  }) async {
    final handle = _projectHandle;
    if (handle == null) {
      return;
    }

    final location = _findClip(clipId);
    if (location == null) {
      return;
    }

    final targetTrack = _tracks[location.trackIndex];
    if (targetTrack.clips.length <= 1) {
      _selectedClipId = clipId;
      notifyListeners();
      return;
    }

    final nextClips = List<TimelineClipData>.from(targetTrack.clips);
    final movedClip = nextClips.removeAt(location.clipIndex);
    final normalizedIndex = insertionIndex.clamp(0, nextClips.length).toInt();
    if (normalizedIndex == location.clipIndex) {
      _selectedClipId = clipId;
      notifyListeners();
      return;
    }

    final previousTracks = _tracks;
    nextClips.insert(normalizedIndex, movedClip);
    final updatedTracks = List<TimelineTrackData>.from(_tracks);
    updatedTracks[location.trackIndex] = targetTrack.copyWith(clips: nextClips);
    _tracks = updatedTracks;
    _selectedClipId = clipId;
    notifyListeners();

    try {
      await _bridge.reorderClip(handle, clipId, normalizedIndex);
      _tracks = await _loadTracksFromEngine(handle);
      _selectedClipId = clipId;
      notifyListeners();
    } catch (_) {
      _tracks = previousTracks;
      _selectedClipId = clipId;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setSelectedClipGain(double gain) async {
    final selectedClipId = _selectedClipId;
    final handle = _projectHandle;
    if (selectedClipId == null || handle == null) {
      return;
    }

    final result = _findClip(selectedClipId);
    if (result == null || result.clip.type != TimelineClipType.media) {
      return;
    }

    await _bridge.setClipGain(handle, selectedClipId, gain.clamp(0.0, 1.0));
    notifyListeners();
  }

  Future<void> setSelectedClipMuted(bool muted) async {
    final selectedClipId = _selectedClipId;
    final handle = _projectHandle;
    if (selectedClipId == null || handle == null) {
      return;
    }

    final result = _findClip(selectedClipId);
    if (result == null || result.clip.type != TimelineClipType.media) {
      return;
    }

    await _bridge.setClipMuted(handle, selectedClipId, muted);
    notifyListeners();
  }

  Future<void> insertClip({
    required EngineTrackKind trackKind,
    required String clipId,
    required String assetId,
    required double durationSeconds,
    bool isMedia = true,
  }) async {
    final handle = _projectHandle;
    if (handle == null) {
      return;
    }

    await _bridge.insertClip(
      handle,
      EngineInsertClipRequest(
        trackKind: trackKind,
        clipId: clipId,
        assetId: assetId,
        durationSeconds: durationSeconds,
        isMedia: isMedia,
      ),
    );
    _tracks = await _loadTracksFromEngine(handle);
    if (!_containsClipId(clipId)) {
      throw StateError(
        'Engine rejected clip $clipId. Verify asset metadata and duration normalization.',
      );
    }
    _selectedClipId = clipId;
    notifyListeners();
  }

  Future<void> importAsset(EngineAssetDescriptor asset) async {
    final handle = _projectHandle;
    if (handle == null) {
      return;
    }

    await _bridge.importAsset(handle, asset);
    _assetRegistry[asset.id] = asset;
    notifyListeners();
  }

  Future<List<TimelineTrackData>> _loadTracksFromEngine(
    EngineProjectHandle handle,
  ) async {
    final snapshot = await _bridge.fetchTimelineTracks(handle);
    if (snapshot.isEmpty) {
      return const <TimelineTrackData>[];
    }

    return snapshot.map(_mapEngineTrack).toList(growable: false);
  }

  TimelineTrackData _mapEngineTrack(EngineTimelineTrackSnapshot track) {
    final kind = _mapTrackKind(track.kind);
    return TimelineTrackData(
      kind: kind,
      placeholderLabel: _placeholderLabelFor(kind),
      clips: [
        for (var i = 0; i < track.clips.length; i++)
          _mapEngineClip(kind, track.clips[i], i),
      ],
    );
  }

  TimelineTrackKind _mapTrackKind(EngineTrackKind kind) {
    switch (kind) {
      case EngineTrackKind.video:
        return TimelineTrackKind.video;
      case EngineTrackKind.image:
        return TimelineTrackKind.image;
      case EngineTrackKind.audio:
        return TimelineTrackKind.audio;
      case EngineTrackKind.text:
        return TimelineTrackKind.text;
      case EngineTrackKind.lipSync:
        return TimelineTrackKind.lipSync;
      case EngineTrackKind.effect:
        return TimelineTrackKind.video;
    }
  }

  TimelineClipData _mapEngineClip(
    TimelineTrackKind trackKind,
    EngineTimelineClipSnapshot clip,
    int index,
  ) {
    final isMedia = clip.isMedia;
    final tone = switch (trackKind) {
      TimelineTrackKind.video => isMedia
          ? (index == 0 ? TimelineClipTone.hero : TimelineClipTone.heroMuted)
          : TimelineClipTone.placeholder,
      _ => isMedia ? TimelineClipTone.heroMuted : TimelineClipTone.placeholder,
    };

    return TimelineClipData(
      id: clip.id,
      duration: clip.durationSeconds,
      type: isMedia ? TimelineClipType.media : TimelineClipType.placeholder,
      tone: tone,
      assetId: clip.assetId,
      sourceOffsetSeconds: clip.sourceOffsetSeconds,
      label: isMedia ? null : _placeholderLabelFor(trackKind),
      splitGroupId: clip.splitGroupId,
    );
  }

  String? _placeholderLabelFor(TimelineTrackKind kind) {
    switch (kind) {
      case TimelineTrackKind.video:
        return null;
      case TimelineTrackKind.image:
        return 'Add image';
      case TimelineTrackKind.audio:
        return 'Add audio';
      case TimelineTrackKind.text:
        return 'Add text';
      case TimelineTrackKind.lipSync:
        return 'Lip sync';
    }
  }

  bool _containsClipId(String clipId) =>
      _tracks.any((track) => track.clips.any((clip) => clip.id == clipId));

  String? _findNewestClipIdByPrefix(String prefix) {
    String? match;
    for (final track in _tracks) {
      for (final clip in track.clips) {
        if (clip.id.startsWith(prefix)) {
          match = clip.id;
        }
      }
    }
    return match;
  }

  String? _firstAvailableClipId() {
    for (final track in _tracks) {
      if (track.clips.isNotEmpty) {
        return track.clips.first.id;
      }
    }
    return null;
  }

  _ClipLocation? _findClip(String clipId) {
    for (var trackIndex = 0; trackIndex < _tracks.length; trackIndex++) {
      var elapsed = 0.0;
      final clips = _tracks[trackIndex].clips;
      for (var clipIndex = 0; clipIndex < clips.length; clipIndex++) {
        final clip = clips[clipIndex];
        final start = elapsed;
        final end = start + clip.duration;
        if (clip.id == clipId) {
          return _ClipLocation(
            trackIndex: trackIndex,
            clipIndex: clipIndex,
            clip: clip,
            start: start,
            end: end,
          );
        }
        elapsed = end;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  Future<void> shutdown() async {
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    final handle = _projectHandle;
    if (handle != null) {
      await _bridge.disposeProject(handle);
      _projectHandle = null;
    }
    _ready = false;
    _tracks = const <TimelineTrackData>[];
    _assetRegistry.clear();
    _selectedClipId = null;
    _status = const EngineStatusSnapshot(
      playbackState: EnginePlaybackState.stopped,
      position: EngineTimelinePosition(seconds: 0, frame: 0),
      isBuffering: false,
    );
    notifyListeners();
  }
}

class _ClipLocation {
  const _ClipLocation({
    required this.trackIndex,
    required this.clipIndex,
    required this.clip,
    required this.start,
    required this.end,
  });

  final int trackIndex;
  final int clipIndex;
  final TimelineClipData clip;
  final double start;
  final double end;
}

class EngineVisualBinding {
  const EngineVisualBinding({
    required this.clipId,
    required this.asset,
    required this.clipStartSeconds,
    required this.clipEndSeconds,
    required this.clipDurationSeconds,
    required this.sourceStartSeconds,
    required this.sourceEndSeconds,
    required this.sourcePositionSeconds,
  });

  final String clipId;
  final EngineAssetDescriptor asset;
  final double clipStartSeconds;
  final double clipEndSeconds;
  final double clipDurationSeconds;
  final double sourceStartSeconds;
  final double sourceEndSeconds;
  final double sourcePositionSeconds;
}
