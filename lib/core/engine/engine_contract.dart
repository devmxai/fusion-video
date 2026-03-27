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
  });

  final int width;
  final int height;
  final double fps;
  final int sampleRate;
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

  Stream<EngineStatusSnapshot> watchStatus(EngineProjectHandle handle);
}
