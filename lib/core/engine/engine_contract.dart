enum EngineTrackKind {
  video,
  image,
  audio,
  text,
  lipSync,
  effect,
}

enum EnginePlaybackState {
  stopped,
  playing,
  paused,
  scrubbing,
}

class EngineProjectConfig {
  const EngineProjectConfig({
    required this.width,
    required this.height,
    required this.fps,
    required this.sampleRate,
    required this.durationSeconds,
  });

  final int width;
  final int height;
  final double fps;
  final int sampleRate;
  final double durationSeconds;
}

class EngineProjectHandle {
  const EngineProjectHandle(this.id);

  final int id;
}

class EngineAssetDescriptor {
  const EngineAssetDescriptor({
    required this.id,
    required this.uri,
    required this.kind,
  });

  final String id;
  final String uri;
  final EngineTrackKind kind;
}

class EngineTimelinePosition {
  const EngineTimelinePosition({
    required this.seconds,
    required this.frame,
  });

  final double seconds;
  final int frame;
}

class EngineStatusSnapshot {
  const EngineStatusSnapshot({
    required this.playbackState,
    required this.position,
    required this.isBuffering,
  });

  final EnginePlaybackState playbackState;
  final EngineTimelinePosition position;
  final bool isBuffering;
}

class EngineTimelineClipSnapshot {
  const EngineTimelineClipSnapshot({
    required this.id,
    required this.durationSeconds,
    required this.isMedia,
    this.splitGroupId,
  });

  final String id;
  final double durationSeconds;
  final bool isMedia;
  final String? splitGroupId;
}

class EngineTimelineTrackSnapshot {
  const EngineTimelineTrackSnapshot({
    required this.kind,
    required this.clips,
  });

  final EngineTrackKind kind;
  final List<EngineTimelineClipSnapshot> clips;
}

class EngineInsertClipRequest {
  const EngineInsertClipRequest({
    required this.trackKind,
    required this.clipId,
    required this.durationSeconds,
    required this.isMedia,
  });

  final EngineTrackKind trackKind;
  final String clipId;
  final double durationSeconds;
  final bool isMedia;
}

abstract class FusionVideoEngineBridge {
  Future<void> initialize();

  Future<EngineProjectHandle> createProject(EngineProjectConfig config);

  Future<void> disposeProject(EngineProjectHandle handle);

  Future<void> importAsset(
    EngineProjectHandle handle,
    EngineAssetDescriptor asset,
  );

  Future<void> play(EngineProjectHandle handle);

  Future<void> pause(EngineProjectHandle handle);

  Future<void> seek(
    EngineProjectHandle handle,
    EngineTimelinePosition position,
  );

  Future<void> splitSelectedClip(
    EngineProjectHandle handle,
    String clipId,
    EngineTimelinePosition position,
  );

  Future<void> trimClipLeft(
    EngineProjectHandle handle,
    String clipId,
    EngineTimelinePosition position,
  );

  Future<void> trimClipRight(
    EngineProjectHandle handle,
    String clipId,
    EngineTimelinePosition position,
  );

  Future<void> deleteClip(
    EngineProjectHandle handle,
    String clipId,
  );

  Future<void> duplicateClip(
    EngineProjectHandle handle,
    String clipId,
  );

  Future<void> insertClip(
    EngineProjectHandle handle,
    EngineInsertClipRequest request,
  );

  Future<List<EngineTimelineTrackSnapshot>> fetchTimelineTracks(
    EngineProjectHandle handle,
  );

  Stream<EngineStatusSnapshot> watchStatus(EngineProjectHandle handle);
}
