import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:convert';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'engine_contract.dart';

typedef _EngineVersionNative = ffi.Uint32 Function();
typedef _EngineVersionDart = int Function();
typedef _EngineCreateProjectNative = ffi.Int64 Function(
  ffi.Uint32 width,
  ffi.Uint32 height,
  ffi.Double fps,
  ffi.Uint32 sampleRate,
  ffi.Double durationSeconds,
);
typedef _EngineCreateProjectDart = int Function(
  int width,
  int height,
  double fps,
  int sampleRate,
  double durationSeconds,
);
typedef _EngineDisposeProjectNative = ffi.Uint8 Function(ffi.Int64 handle);
typedef _EngineDisposeProjectDart = int Function(int handle);
typedef _EnginePlayNative = ffi.Uint8 Function(ffi.Int64 handle);
typedef _EnginePlayDart = int Function(int handle);
typedef _EnginePauseNative = ffi.Uint8 Function(ffi.Int64 handle);
typedef _EnginePauseDart = int Function(int handle);
typedef _EngineSeekNative = ffi.Uint8 Function(
  ffi.Int64 handle,
  ffi.Double seconds,
  ffi.Int64 frame,
);
typedef _EngineSeekDart = int Function(int handle, double seconds, int frame);
typedef _EngineSplitSelectedClipNative = ffi.Uint8 Function(
  ffi.Int64 handle,
  ffi.Pointer<ffi.Char> clipId,
  ffi.Double seconds,
  ffi.Int64 frame,
);
typedef _EngineSplitSelectedClipDart = int Function(
    int handle, ffi.Pointer<ffi.Char> clipId, double seconds, int frame);
typedef _EngineTrimClipLeftNative = ffi.Uint8 Function(
  ffi.Int64 handle,
  ffi.Pointer<ffi.Char> clipId,
  ffi.Double seconds,
  ffi.Int64 frame,
);
typedef _EngineTrimClipLeftDart = int Function(
    int handle, ffi.Pointer<ffi.Char> clipId, double seconds, int frame);
typedef _EngineTrimClipRightNative = ffi.Uint8 Function(
  ffi.Int64 handle,
  ffi.Pointer<ffi.Char> clipId,
  ffi.Double seconds,
  ffi.Int64 frame,
);
typedef _EngineTrimClipRightDart = int Function(
    int handle, ffi.Pointer<ffi.Char> clipId, double seconds, int frame);
typedef _EngineDeleteClipNative = ffi.Uint8 Function(
  ffi.Int64 handle,
  ffi.Pointer<ffi.Char> clipId,
);
typedef _EngineDeleteClipDart = int Function(
    int handle, ffi.Pointer<ffi.Char> clipId);
typedef _EngineDuplicateClipNative = ffi.Uint8 Function(
  ffi.Int64 handle,
  ffi.Pointer<ffi.Char> clipId,
);
typedef _EngineDuplicateClipDart = int Function(
    int handle, ffi.Pointer<ffi.Char> clipId);
typedef _EngineInsertClipNative = ffi.Uint8 Function(
  ffi.Int64 handle,
  ffi.Uint8 trackKind,
  ffi.Pointer<ffi.Char> clipId,
  ffi.Double durationSeconds,
  ffi.Uint8 isMedia,
);
typedef _EngineInsertClipDart = int Function(
  int handle,
  int trackKind,
  ffi.Pointer<ffi.Char> clipId,
  double durationSeconds,
  int isMedia,
);
typedef _EngineGetPlaybackStateNative = ffi.Uint8 Function(ffi.Int64 handle);
typedef _EngineGetPlaybackStateDart = int Function(int handle);
typedef _EngineGetPositionSecondsNative = ffi.Double Function(ffi.Int64 handle);
typedef _EngineGetPositionSecondsDart = double Function(int handle);
typedef _EngineGetPositionFrameNative = ffi.Int64 Function(ffi.Int64 handle);
typedef _EngineGetPositionFrameDart = int Function(int handle);
typedef _EngineIsBufferingNative = ffi.Uint8 Function(ffi.Int64 handle);
typedef _EngineIsBufferingDart = int Function(int handle);
typedef _EngineGetTimelineJsonNative = ffi.Pointer<Utf8> Function(
    ffi.Int64 handle);
typedef _EngineGetTimelineJsonDart = ffi.Pointer<Utf8> Function(int handle);
typedef _EngineFreeStringNative = ffi.Void Function(ffi.Pointer<Utf8> value);
typedef _EngineFreeStringDart = void Function(ffi.Pointer<Utf8> value);

class FusionVideoFfiBridge implements FusionVideoEngineBridge {
  FusionVideoFfiBridge._(ffi.DynamicLibrary library)
      : _engineVersion =
            library.lookupFunction<_EngineVersionNative, _EngineVersionDart>(
          'fusion_video_engine_version',
        ),
        _engineCreateProject = library.lookupFunction<
            _EngineCreateProjectNative,
            _EngineCreateProjectDart>('fusion_video_engine_create_project'),
        _engineDisposeProject = library.lookupFunction<
            _EngineDisposeProjectNative,
            _EngineDisposeProjectDart>('fusion_video_engine_dispose_project'),
        _enginePlay =
            library.lookupFunction<_EnginePlayNative, _EnginePlayDart>(
          'fusion_video_engine_play',
        ),
        _enginePause =
            library.lookupFunction<_EnginePauseNative, _EnginePauseDart>(
          'fusion_video_engine_pause',
        ),
        _engineSeek =
            library.lookupFunction<_EngineSeekNative, _EngineSeekDart>(
          'fusion_video_engine_seek',
        ),
        _engineSplitSelectedClip = library.lookupFunction<
                _EngineSplitSelectedClipNative, _EngineSplitSelectedClipDart>(
            'fusion_video_engine_split_selected_clip'),
        _engineTrimClipLeft = library.lookupFunction<_EngineTrimClipLeftNative,
            _EngineTrimClipLeftDart>('fusion_video_engine_trim_clip_left'),
        _engineTrimClipRight = library.lookupFunction<
            _EngineTrimClipRightNative,
            _EngineTrimClipRightDart>('fusion_video_engine_trim_clip_right'),
        _engineDeleteClip = library.lookupFunction<_EngineDeleteClipNative,
            _EngineDeleteClipDart>('fusion_video_engine_delete_clip'),
        _engineDuplicateClip = library.lookupFunction<
            _EngineDuplicateClipNative,
            _EngineDuplicateClipDart>('fusion_video_engine_duplicate_clip'),
        _engineInsertClip = library.lookupFunction<_EngineInsertClipNative,
            _EngineInsertClipDart>('fusion_video_engine_insert_clip'),
        _engineGetPlaybackState = library.lookupFunction<
                _EngineGetPlaybackStateNative, _EngineGetPlaybackStateDart>(
            'fusion_video_engine_get_playback_state'),
        _engineGetPositionSeconds = library.lookupFunction<
                _EngineGetPositionSecondsNative, _EngineGetPositionSecondsDart>(
            'fusion_video_engine_get_position_seconds'),
        _engineGetPositionFrame = library.lookupFunction<
                _EngineGetPositionFrameNative, _EngineGetPositionFrameDart>(
            'fusion_video_engine_get_position_frame'),
        _engineIsBuffering = library
            .lookupFunction<_EngineIsBufferingNative, _EngineIsBufferingDart>(
          'fusion_video_engine_is_buffering',
        ),
        _engineGetTimelineJson = library.lookupFunction<
                _EngineGetTimelineJsonNative, _EngineGetTimelineJsonDart>(
            'fusion_video_engine_get_timeline_json'),
        _engineFreeString = library
            .lookupFunction<_EngineFreeStringNative, _EngineFreeStringDart>(
          'fusion_video_engine_free_string',
        );

  final _EngineVersionDart _engineVersion;
  final _EngineCreateProjectDart _engineCreateProject;
  final _EngineDisposeProjectDart _engineDisposeProject;
  final _EnginePlayDart _enginePlay;
  final _EnginePauseDart _enginePause;
  final _EngineSeekDart _engineSeek;
  final _EngineSplitSelectedClipDart _engineSplitSelectedClip;
  final _EngineTrimClipLeftDart _engineTrimClipLeft;
  final _EngineTrimClipRightDart _engineTrimClipRight;
  final _EngineDeleteClipDart _engineDeleteClip;
  final _EngineDuplicateClipDart _engineDuplicateClip;
  final _EngineInsertClipDart _engineInsertClip;
  final _EngineGetPlaybackStateDart _engineGetPlaybackState;
  final _EngineGetPositionSecondsDart _engineGetPositionSeconds;
  final _EngineGetPositionFrameDart _engineGetPositionFrame;
  final _EngineIsBufferingDart _engineIsBuffering;
  final _EngineGetTimelineJsonDart _engineGetTimelineJson;
  final _EngineFreeStringDart _engineFreeString;

  final Map<int, _FfiProjectFeed> _projects = {};

  static FusionVideoFfiBridge? tryCreate() {
    final library = _tryLoadLibrary();
    if (library == null) {
      return null;
    }

    try {
      return FusionVideoFfiBridge._(library);
    } catch (_) {
      return null;
    }
  }

  static ffi.DynamicLibrary? _tryLoadLibrary() {
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        return ffi.DynamicLibrary.process();
      }
    } catch (_) {
      // Fall through to file-based lookups.
    }

    for (final path in _candidatePaths()) {
      try {
        return ffi.DynamicLibrary.open(path);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static Iterable<String> _candidatePaths() sync* {
    if (Platform.isAndroid) {
      yield 'libfusion_video_engine.so';
    } else if (Platform.isIOS) {
      yield 'fusion_video_engine.framework/fusion_video_engine';
    } else if (Platform.isMacOS) {
      yield 'libfusion_video_engine.dylib';
      yield 'engine/rust_core/target/release/libfusion_video_engine.dylib';
    }
  }

  int get version => _engineVersion();

  _FfiProjectFeed _feedFor(EngineProjectHandle handle) {
    final feed = _projects[handle.id];
    if (feed == null) {
      throw StateError('Unknown engine project: ${handle.id}');
    }
    return feed;
  }

  EngineStatusSnapshot _readSnapshot(int handleId) {
    final stateIndex = _engineGetPlaybackState(handleId)
        .clamp(0, EnginePlaybackState.values.length - 1);
    return EngineStatusSnapshot(
      playbackState: EnginePlaybackState.values[stateIndex],
      position: EngineTimelinePosition(
        seconds: _engineGetPositionSeconds(handleId),
        frame: _engineGetPositionFrame(handleId),
      ),
      isBuffering: _engineIsBuffering(handleId) != 0,
    );
  }

  void _emitSnapshot(int handleId, {bool force = false}) {
    final feed = _projects[handleId];
    if (feed == null || feed.controller.isClosed) {
      return;
    }

    final snapshot = _readSnapshot(handleId);
    final previous = feed.lastSnapshot;
    final changed = force ||
        previous == null ||
        previous.playbackState != snapshot.playbackState ||
        previous.position.frame != snapshot.position.frame ||
        (previous.position.seconds - snapshot.position.seconds).abs() >
            0.0001 ||
        previous.isBuffering != snapshot.isBuffering;

    if (!changed) {
      return;
    }

    feed.lastSnapshot = snapshot;
    feed.controller.add(snapshot);
  }

  void _startPolling(int handleId) {
    final feed = _projects[handleId];
    if (feed == null || feed.timer != null) {
      return;
    }

    feed.timer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _emitSnapshot(handleId),
    );
  }

  void _ensureSuccess(int result, String action) {
    if (result == 0) {
      throw StateError('Fusion Video engine failed to $action.');
    }
  }

  EngineTrackKind _parseTrackKind(String value) {
    switch (value) {
      case 'Video':
        return EngineTrackKind.video;
      case 'Image':
        return EngineTrackKind.image;
      case 'Audio':
        return EngineTrackKind.audio;
      case 'Text':
        return EngineTrackKind.text;
      case 'LipSync':
        return EngineTrackKind.lipSync;
      default:
        return EngineTrackKind.effect;
    }
  }

  bool _parseClipMedia(String value) => value == 'Media';

  @override
  Future<void> initialize() async {
    version;
  }

  @override
  Future<EngineProjectHandle> createProject(EngineProjectConfig config) async {
    final id = _engineCreateProject(
      config.width,
      config.height,
      config.fps,
      config.sampleRate,
      config.durationSeconds,
    );
    if (id <= 0) {
      throw StateError('Failed to create Fusion Video engine project.');
    }

    final feed = _FfiProjectFeed();
    _projects[id] = feed;
    _startPolling(id);
    return EngineProjectHandle(id);
  }

  @override
  Future<void> disposeProject(EngineProjectHandle handle) async {
    _engineDisposeProject(handle.id);
    final feed = _projects.remove(handle.id);
    feed?.dispose();
  }

  @override
  Future<void> importAsset(
    EngineProjectHandle handle,
    EngineAssetDescriptor asset,
  ) async {}

  @override
  Future<void> play(EngineProjectHandle handle) async {
    _ensureSuccess(_enginePlay(handle.id), 'play');
    _emitSnapshot(handle.id, force: true);
  }

  @override
  Future<void> pause(EngineProjectHandle handle) async {
    _ensureSuccess(_enginePause(handle.id), 'pause');
    _emitSnapshot(handle.id, force: true);
  }

  @override
  Future<void> seek(
    EngineProjectHandle handle,
    EngineTimelinePosition position,
  ) async {
    _ensureSuccess(
      _engineSeek(handle.id, position.seconds, position.frame),
      'seek',
    );
    _emitSnapshot(handle.id, force: true);
  }

  @override
  Future<void> splitSelectedClip(
    EngineProjectHandle handle,
    String clipId,
    EngineTimelinePosition position,
  ) async {
    final nativeClipId = clipId.toNativeUtf8();
    try {
      _ensureSuccess(
        _engineSplitSelectedClip(
          handle.id,
          nativeClipId.cast(),
          position.seconds,
          position.frame,
        ),
        'split clip',
      );
    } finally {
      malloc.free(nativeClipId);
    }
  }

  @override
  Future<void> trimClipLeft(
    EngineProjectHandle handle,
    String clipId,
    EngineTimelinePosition position,
  ) async {
    final nativeClipId = clipId.toNativeUtf8();
    try {
      _ensureSuccess(
        _engineTrimClipLeft(
          handle.id,
          nativeClipId.cast(),
          position.seconds,
          position.frame,
        ),
        'trim clip left',
      );
    } finally {
      malloc.free(nativeClipId);
    }
  }

  @override
  Future<void> trimClipRight(
    EngineProjectHandle handle,
    String clipId,
    EngineTimelinePosition position,
  ) async {
    final nativeClipId = clipId.toNativeUtf8();
    try {
      _ensureSuccess(
        _engineTrimClipRight(
          handle.id,
          nativeClipId.cast(),
          position.seconds,
          position.frame,
        ),
        'trim clip right',
      );
    } finally {
      malloc.free(nativeClipId);
    }
  }

  @override
  Future<void> deleteClip(EngineProjectHandle handle, String clipId) async {
    final nativeClipId = clipId.toNativeUtf8();
    try {
      _ensureSuccess(
        _engineDeleteClip(handle.id, nativeClipId.cast()),
        'delete clip',
      );
    } finally {
      malloc.free(nativeClipId);
    }
  }

  @override
  Future<void> duplicateClip(EngineProjectHandle handle, String clipId) async {
    final nativeClipId = clipId.toNativeUtf8();
    try {
      _ensureSuccess(
        _engineDuplicateClip(handle.id, nativeClipId.cast()),
        'duplicate clip',
      );
    } finally {
      malloc.free(nativeClipId);
    }
  }

  @override
  Future<void> insertClip(
    EngineProjectHandle handle,
    EngineInsertClipRequest request,
  ) async {
    final nativeClipId = request.clipId.toNativeUtf8();
    try {
      _ensureSuccess(
        _engineInsertClip(
          handle.id,
          request.trackKind.index,
          nativeClipId.cast(),
          request.durationSeconds,
          request.isMedia ? 1 : 0,
        ),
        'insert clip',
      );
    } finally {
      malloc.free(nativeClipId);
    }
  }

  @override
  Future<List<EngineTimelineTrackSnapshot>> fetchTimelineTracks(
    EngineProjectHandle handle,
  ) async {
    final pointer = _engineGetTimelineJson(handle.id);
    if (pointer == ffi.nullptr) {
      throw StateError(
          'Fusion Video engine failed to fetch timeline snapshot.');
    }

    try {
      final jsonString = pointer.toDartString();
      final decoded = jsonDecode(jsonString) as List<dynamic>;
      return decoded.map((dynamic trackEntry) {
        final trackMap = trackEntry as Map<String, dynamic>;
        final clips =
            (trackMap['clips'] as List<dynamic>).map((dynamic clipEntry) {
          final clipMap = clipEntry as Map<String, dynamic>;
          return EngineTimelineClipSnapshot(
            id: clipMap['id'] as String,
            durationSeconds: (clipMap['duration_seconds'] as num).toDouble(),
            isMedia: _parseClipMedia(clipMap['clip_type'] as String),
            splitGroupId: clipMap['split_group_id'] as String?,
          );
        }).toList(growable: false);

        return EngineTimelineTrackSnapshot(
          kind: _parseTrackKind(trackMap['kind'] as String),
          clips: clips,
        );
      }).toList(growable: false);
    } finally {
      _engineFreeString(pointer);
    }
  }

  @override
  Stream<EngineStatusSnapshot> watchStatus(EngineProjectHandle handle) {
    final feed = _feedFor(handle);
    scheduleMicrotask(() => _emitSnapshot(handle.id, force: true));
    return feed.controller.stream;
  }
}

class _FfiProjectFeed {
  final StreamController<EngineStatusSnapshot> controller =
      StreamController<EngineStatusSnapshot>.broadcast();
  Timer? timer;
  EngineStatusSnapshot? lastSnapshot;

  void dispose() {
    timer?.cancel();
    controller.close();
  }
}
