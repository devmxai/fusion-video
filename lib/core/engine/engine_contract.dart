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
    this.label,
    this.durationSeconds,
    this.width,
    this.height,
  });

  final String id;
  final String uri;
  final EngineTrackKind kind;
  final String? label;
  final double? durationSeconds;
  final int? width;
  final int? height;
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
    this.assetId,
    this.sourceOffsetSeconds,
    this.splitGroupId,
    this.audioGain = 1.0,
    this.isMuted = false,
  });

  final String id;
  final double durationSeconds;
  final bool isMedia;
  final String? assetId;
  final double? sourceOffsetSeconds;
  final String? splitGroupId;
  final double audioGain;
  final bool isMuted;
}

class EngineTimelineTrackSnapshot {
  const EngineTimelineTrackSnapshot({
    required this.kind,
    required this.clips,
  });

  final EngineTrackKind kind;
  final List<EngineTimelineClipSnapshot> clips;
}

class EngineVisualTransformSnapshot {
  const EngineVisualTransformSnapshot({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.opacity,
    required this.rotationDegrees,
    required this.zIndex,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double opacity;
  final double rotationDegrees;
  final int zIndex;
}

class EngineCompositionNodeSnapshot {
  const EngineCompositionNodeSnapshot({
    required this.clipId,
    required this.assetId,
    required this.trackKind,
    required this.assetUri,
    this.displayLabel,
    required this.clipStartSeconds,
    required this.clipEndSeconds,
    required this.clipDurationSeconds,
    required this.sourceStartSeconds,
    required this.sourceEndSeconds,
    required this.sourcePositionSeconds,
    required this.transform,
  });

  final String clipId;
  final String assetId;
  final EngineTrackKind trackKind;
  final String assetUri;
  final String? displayLabel;
  final double clipStartSeconds;
  final double clipEndSeconds;
  final double clipDurationSeconds;
  final double sourceStartSeconds;
  final double sourceEndSeconds;
  final double sourcePositionSeconds;
  final EngineVisualTransformSnapshot transform;
}

class EngineAudioNodeSnapshot {
  const EngineAudioNodeSnapshot({
    required this.clipId,
    required this.assetId,
    required this.trackKind,
    required this.assetUri,
    this.displayLabel,
    required this.clipStartSeconds,
    required this.clipEndSeconds,
    required this.clipDurationSeconds,
    required this.sourceStartSeconds,
    required this.sourceEndSeconds,
    required this.sourcePositionSeconds,
    required this.gain,
    required this.isMuted,
  });

  final String clipId;
  final String assetId;
  final EngineTrackKind trackKind;
  final String assetUri;
  final String? displayLabel;
  final double clipStartSeconds;
  final double clipEndSeconds;
  final double clipDurationSeconds;
  final double sourceStartSeconds;
  final double sourceEndSeconds;
  final double sourcePositionSeconds;
  final double gain;
  final bool isMuted;
}

class EngineInsertClipRequest {
  const EngineInsertClipRequest({
    required this.trackKind,
    required this.clipId,
    required this.assetId,
    required this.durationSeconds,
    required this.isMedia,
  });

  final EngineTrackKind trackKind;
  final String clipId;
  final String assetId;
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

  Future<void> setClipGain(
    EngineProjectHandle handle,
    String clipId,
    double gain,
  );

  Future<void> setClipMuted(
    EngineProjectHandle handle,
    String clipId,
    bool muted,
  );

  Future<void> insertClip(
    EngineProjectHandle handle,
    EngineInsertClipRequest request,
  );

  Future<List<EngineTimelineTrackSnapshot>> fetchTimelineTracks(
    EngineProjectHandle handle,
  );

  Future<List<EngineCompositionNodeSnapshot>> fetchCompositionNodes(
    EngineProjectHandle handle,
    EngineTimelinePosition position,
  );

  Future<List<EngineAudioNodeSnapshot>> fetchAudioNodes(
    EngineProjectHandle handle,
    EngineTimelinePosition position,
  );

  Stream<EngineStatusSnapshot> watchStatus(EngineProjectHandle handle);
}
