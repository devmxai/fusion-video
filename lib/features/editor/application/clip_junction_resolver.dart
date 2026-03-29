import '../../../core/engine/engine_contract.dart';
import '../../../core/preview/preview_backend.dart';
import '../presentation/models/timeline_mock_models.dart';

enum ClipJunctionKind {
  sameSourceContiguous,
  sameSourceNonContiguous,
  differentSource,
  videoToImage,
}

class ClipJunction {
  const ClipJunction({
    required this.kind,
    required this.leadingClipId,
    required this.trailingClipId,
    required this.seamProjectSeconds,
  });

  final ClipJunctionKind kind;
  final String leadingClipId;
  final String trailingClipId;
  final double seamProjectSeconds;
}

class ClipJunctionResolution {
  const ClipJunctionResolution({
    required this.activeSource,
    required this.activeClipIds,
    this.leadingJunction,
    this.trailingJunction,
    this.upcomingSource,
  });

  final PreviewSource activeSource;
  final List<String> activeClipIds;
  final ClipJunction? leadingJunction;
  final ClipJunction? trailingJunction;
  final PreviewSource? upcomingSource;
}

class ClipJunctionResolver {
  const ClipJunctionResolver._();

  static ClipJunctionResolution? resolvePlayback({
    required EngineCompositionNodeSnapshot targetNode,
    required List<TimelineTrackData> tracks,
    required EngineAssetDescriptor? Function(String assetId) assetResolver,
    required bool isPlaying,
  }) {
    final resolvedTrack = _resolveTrackSegments(
      tracks: tracks,
      assetResolver: assetResolver,
      targetClipId: targetNode.clipId,
    );
    if (resolvedTrack.isEmpty) {
      return null;
    }

    final targetIndex = resolvedTrack.indexWhere(
      (segment) => segment.clip.id == targetNode.clipId,
    );
    if (targetIndex < 0) {
      return null;
    }

    var groupStartIndex = targetIndex;
    var groupEndIndex = targetIndex;
    while (groupStartIndex > 0) {
      final junction = _classifyBoundary(
        resolvedTrack[groupStartIndex - 1],
        resolvedTrack[groupStartIndex],
      );
      if (junction.kind != ClipJunctionKind.sameSourceContiguous) {
        break;
      }
      groupStartIndex -= 1;
    }
    while (groupEndIndex < resolvedTrack.length - 1) {
      final junction = _classifyBoundary(
        resolvedTrack[groupEndIndex],
        resolvedTrack[groupEndIndex + 1],
      );
      if (junction.kind != ClipJunctionKind.sameSourceContiguous) {
        break;
      }
      groupEndIndex += 1;
    }

    final activeSource = _buildPreviewSource(
      segments: resolvedTrack,
      startIndex: groupStartIndex,
      endIndex: groupEndIndex,
    );
    final leadingJunction = groupStartIndex == 0
        ? null
        : _classifyBoundary(
            resolvedTrack[groupStartIndex - 1],
            resolvedTrack[groupStartIndex],
          );
    final trailingJunction = groupEndIndex >= resolvedTrack.length - 1
        ? null
        : _classifyBoundary(
            resolvedTrack[groupEndIndex],
            resolvedTrack[groupEndIndex + 1],
          );

    PreviewSource? upcomingSource;
    if (trailingJunction != null && groupEndIndex < resolvedTrack.length - 1) {
      final nextGroupStart = groupEndIndex + 1;
      var nextGroupEnd = nextGroupStart;
      while (nextGroupEnd < resolvedTrack.length - 1) {
        final junction = _classifyBoundary(
          resolvedTrack[nextGroupEnd],
          resolvedTrack[nextGroupEnd + 1],
        );
        if (junction.kind != ClipJunctionKind.sameSourceContiguous) {
          break;
        }
        nextGroupEnd += 1;
      }
      upcomingSource = _buildPreviewSource(
        segments: resolvedTrack,
        startIndex: nextGroupStart,
        endIndex: nextGroupEnd,
      );
    }

    return ClipJunctionResolution(
      activeSource: activeSource,
      activeClipIds: resolvedTrack
          .sublist(groupStartIndex, groupEndIndex + 1)
          .map((segment) => segment.clip.id)
          .toList(growable: false),
      leadingJunction: leadingJunction,
      trailingJunction: trailingJunction,
      upcomingSource: upcomingSource,
    );
  }

  static List<_ResolvedVisualSegment> _resolveTrackSegments({
    required List<TimelineTrackData> tracks,
    required EngineAssetDescriptor? Function(String assetId) assetResolver,
    required String targetClipId,
  }) {
    for (final track in tracks) {
      if (!_isVisualTrack(track.kind)) {
        continue;
      }
      if (!track.clips.any((clip) => clip.id == targetClipId)) {
        continue;
      }

      final segments = <_ResolvedVisualSegment>[];
      var elapsed = 0.0;
      for (final clip in track.clips) {
        final start = elapsed;
        final end = start + clip.duration;
        elapsed = end;

        if (clip.type != TimelineClipType.media || clip.assetId == null) {
          continue;
        }

        final asset = assetResolver(clip.assetId!);
        segments.add(
          _ResolvedVisualSegment(
            clip: clip,
            trackKind: asset?.kind ?? _mapTrackKind(track.kind),
            clipStartSeconds: start,
            clipEndSeconds: end,
            assetId: clip.assetId!,
            asset: asset,
          ),
        );
      }
      return segments;
    }
    return const <_ResolvedVisualSegment>[];
  }

  static ClipJunction _classifyBoundary(
    _ResolvedVisualSegment left,
    _ResolvedVisualSegment right,
  ) {
    if ((left.trackKind == EngineTrackKind.video &&
            right.trackKind == EngineTrackKind.image) ||
        (left.trackKind == EngineTrackKind.image &&
            right.trackKind == EngineTrackKind.video)) {
      return ClipJunction(
        kind: ClipJunctionKind.videoToImage,
        leadingClipId: left.clip.id,
        trailingClipId: right.clip.id,
        seamProjectSeconds: left.clipEndSeconds,
      );
    }

    if (left.assetId == right.assetId && left.trackKind == right.trackKind) {
      final leftSourceEnd =
          (left.clip.sourceOffsetSeconds ?? 0) + left.clip.duration;
      final rightSourceStart = right.clip.sourceOffsetSeconds ?? 0;
      return ClipJunction(
        kind: (leftSourceEnd - rightSourceStart).abs() <= 0.001
            ? ClipJunctionKind.sameSourceContiguous
            : ClipJunctionKind.sameSourceNonContiguous,
        leadingClipId: left.clip.id,
        trailingClipId: right.clip.id,
        seamProjectSeconds: left.clipEndSeconds,
      );
    }

    return ClipJunction(
      kind: ClipJunctionKind.differentSource,
      leadingClipId: left.clip.id,
      trailingClipId: right.clip.id,
      seamProjectSeconds: left.clipEndSeconds,
    );
  }

  static PreviewSource _buildPreviewSource({
    required List<_ResolvedVisualSegment> segments,
    required int startIndex,
    required int endIndex,
  }) {
    final first = segments[startIndex];
    final last = segments[endIndex];
    final descriptor = first.asset;
    final sourceStartSeconds = first.clip.sourceOffsetSeconds ?? 0;
    final clipDurationSeconds =
        last.clipEndSeconds - first.clipStartSeconds;
    final sourceEndSeconds =
        (last.clip.sourceOffsetSeconds ?? 0) + last.clip.duration;
    final attachmentId = [
      first.assetId,
      first.trackKind.name,
      first.clipStartSeconds.toStringAsFixed(3),
      last.clipEndSeconds.toStringAsFixed(3),
      sourceStartSeconds.toStringAsFixed(3),
      sourceEndSeconds.toStringAsFixed(3),
    ].join(':');

    return PreviewSource(
      id: attachmentId,
      attachmentId: attachmentId,
      assetId: first.assetId,
      kind: (first.asset?.kind ?? first.trackKind) == EngineTrackKind.video
          ? PreviewSourceKind.video
          : PreviewSourceKind.image,
      localPath: descriptor?.uri ?? '',
      clipStartSeconds: first.clipStartSeconds,
      clipEndSeconds: last.clipEndSeconds,
      durationSeconds: descriptor?.durationSeconds,
      width: descriptor?.width,
      height: descriptor?.height,
      sourceStartSeconds: sourceStartSeconds,
      sourceEndSeconds: sourceEndSeconds,
      clipDurationSeconds: clipDurationSeconds,
    );
  }

  static bool _isVisualTrack(TimelineTrackKind kind) =>
      kind == TimelineTrackKind.video || kind == TimelineTrackKind.image;

  static EngineTrackKind _mapTrackKind(TimelineTrackKind kind) {
    switch (kind) {
      case TimelineTrackKind.video:
        return EngineTrackKind.video;
      case TimelineTrackKind.image:
        return EngineTrackKind.image;
      case TimelineTrackKind.audio:
        return EngineTrackKind.audio;
      case TimelineTrackKind.text:
        return EngineTrackKind.text;
      case TimelineTrackKind.lipSync:
        return EngineTrackKind.lipSync;
    }
  }
}

class _ResolvedVisualSegment {
  const _ResolvedVisualSegment({
    required this.clip,
    required this.trackKind,
    required this.clipStartSeconds,
    required this.clipEndSeconds,
    required this.assetId,
    required this.asset,
  });

  final TimelineClipData clip;
  final EngineTrackKind trackKind;
  final double clipStartSeconds;
  final double clipEndSeconds;
  final String assetId;
  final EngineAssetDescriptor? asset;
}
