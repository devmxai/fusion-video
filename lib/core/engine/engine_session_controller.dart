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

  List<TimelineTrackData> get tracks => List.unmodifiable(_tracks);
  String? get selectedClipId => _selectedClipId;

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

  Future<void> splitSelectedClip() async {
    final selectedClipId = _selectedClipId;
    final handle = _projectHandle;
    if (selectedClipId == null || handle == null) {
      return;
    }

    final updatedTracks = <TimelineTrackData>[];
    var didSplit = false;
    final splitStamp = DateTime.now().microsecondsSinceEpoch.toString();
    final current = currentSeconds;
    const edgePadding = 0.05;

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
          final splitAt = current.clamp(start + edgePadding, end - edgePadding);
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
          _selectedClipId = rightClip.id;
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

    final bridgeSeconds = current.clamp(0.0, durationSeconds).toDouble();
    await _bridge.splitSelectedClip(
      handle,
      selectedClipId,
      EngineTimelinePosition(
        seconds: bridgeSeconds,
        frame: (bridgeSeconds * _config.fps).round(),
      ),
    );
    _tracks = await _loadTracksFromEngine(handle);
    _selectedClipId = _findNewestClipIdByPrefix('${selectedClipId}_b_') ??
        _findNewestClipIdByPrefix('${selectedClipId}_a_') ??
        updatedTracks
            .expand((track) => track.clips)
            .map((clip) => clip.id)
            .firstWhere(
              (id) => _containsClipId(id),
              orElse: () => selectedClipId,
            );
    notifyListeners();
  }

  Future<void> trimSelectedClipLeft() async {
    final selectedClipId = _selectedClipId;
    final handle = _projectHandle;
    if (selectedClipId == null || handle == null) {
      return;
    }

    final result = _findClip(selectedClipId);
    if (result == null || result.clip.type != TimelineClipType.media) {
      return;
    }

    const minDuration = 0.2;
    final newStart = currentSeconds.clamp(
      result.start,
      result.end - minDuration,
    );
    final delta = newStart - result.start;
    if (delta <= 0.01) {
      return;
    }

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
  }

  Future<void> trimSelectedClipRight() async {
    final selectedClipId = _selectedClipId;
    final handle = _projectHandle;
    if (selectedClipId == null || handle == null) {
      return;
    }

    final result = _findClip(selectedClipId);
    if (result == null || result.clip.type != TimelineClipType.media) {
      return;
    }

    const minDuration = 0.2;
    final newEnd = currentSeconds.clamp(
      result.start + minDuration,
      result.end,
    );
    final newDuration = newEnd - result.start;
    if ((newDuration - result.clip.duration).abs() <= 0.01 ||
        newDuration >= result.clip.duration) {
      return;
    }

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

  Future<void> insertClip({
    required EngineTrackKind trackKind,
    required String clipId,
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
        durationSeconds: durationSeconds,
        isMedia: isMedia,
      ),
    );
    _tracks = await _loadTracksFromEngine(handle);
    _selectedClipId = clipId;
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
