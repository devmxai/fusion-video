import 'package:flutter_test/flutter_test.dart';

import 'package:fusion_video/core/engine/engine_contract.dart';
import 'package:fusion_video/features/editor/application/clip_junction_resolver.dart';
import 'package:fusion_video/features/editor/presentation/models/timeline_mock_models.dart';

void main() {
  EngineAssetDescriptor asset({
    required String id,
    required String uri,
    required EngineTrackKind kind,
    double durationSeconds = 4,
  }) {
    return EngineAssetDescriptor(
      id: id,
      uri: uri,
      kind: kind,
      durationSeconds: durationSeconds,
      width: kind == EngineTrackKind.audio ? null : 1080,
      height: kind == EngineTrackKind.audio ? null : 1920,
    );
  }

  TimelineClipData clip({
    required String id,
    required String assetId,
    required double duration,
    required double sourceOffsetSeconds,
  }) {
    return TimelineClipData(
      id: id,
      duration: duration,
      type: TimelineClipType.media,
      tone: TimelineClipTone.hero,
      assetId: assetId,
      sourceOffsetSeconds: sourceOffsetSeconds,
    );
  }

  EngineCompositionNodeSnapshot node({
    required String clipId,
    required String assetId,
    required EngineTrackKind kind,
    required String uri,
    required double clipStartSeconds,
    required double clipEndSeconds,
    required double sourceStartSeconds,
    required double sourceEndSeconds,
  }) {
    return EngineCompositionNodeSnapshot(
      clipId: clipId,
      assetId: assetId,
      trackKind: kind,
      assetUri: uri,
      clipStartSeconds: clipStartSeconds,
      clipEndSeconds: clipEndSeconds,
      clipDurationSeconds: clipEndSeconds - clipStartSeconds,
      sourceStartSeconds: sourceStartSeconds,
      sourceEndSeconds: sourceEndSeconds,
      sourcePositionSeconds: sourceStartSeconds,
      transform: const EngineVisualTransformSnapshot(
        x: 0,
        y: 0,
        width: 1080,
        height: 1920,
        opacity: 1,
        rotationDegrees: 0,
        zIndex: 0,
      ),
    );
  }

  test('split seam from same contiguous source resolves to one playback group',
      () {
    final assets = <String, EngineAssetDescriptor>{
      'video-1': asset(
        id: 'video-1',
        uri: '/tmp/video-1.mp4',
        kind: EngineTrackKind.video,
      ),
    };
    final tracks = [
      TimelineTrackData(
        kind: TimelineTrackKind.video,
        clips: [
          clip(
            id: 'video-1_a',
            assetId: 'video-1',
            duration: 1.5,
            sourceOffsetSeconds: 0,
          ),
          clip(
            id: 'video-1_b',
            assetId: 'video-1',
            duration: 2.5,
            sourceOffsetSeconds: 1.5,
          ),
        ],
      ),
    ];

    final leftResolution = ClipJunctionResolver.resolvePlayback(
      targetNode: node(
        clipId: 'video-1_a',
        assetId: 'video-1',
        kind: EngineTrackKind.video,
        uri: '/tmp/video-1.mp4',
        clipStartSeconds: 0,
        clipEndSeconds: 1.5,
        sourceStartSeconds: 0,
        sourceEndSeconds: 1.5,
      ),
      tracks: tracks,
      assetResolver: (assetId) => assets[assetId],
      isPlaying: true,
    );
    final rightResolution = ClipJunctionResolver.resolvePlayback(
      targetNode: node(
        clipId: 'video-1_b',
        assetId: 'video-1',
        kind: EngineTrackKind.video,
        uri: '/tmp/video-1.mp4',
        clipStartSeconds: 1.5,
        clipEndSeconds: 4,
        sourceStartSeconds: 1.5,
        sourceEndSeconds: 4,
      ),
      tracks: tracks,
      assetResolver: (assetId) => assets[assetId],
      isPlaying: true,
    );

    expect(leftResolution, isNotNull);
    expect(rightResolution, isNotNull);
    expect(
      leftResolution!.activeSource.effectiveAttachmentId,
      rightResolution!.activeSource.effectiveAttachmentId,
    );
    expect(leftResolution.activeSource.clipStartSeconds, closeTo(0, 0.001));
    expect(leftResolution.activeSource.clipEndSeconds, closeTo(4, 0.001));
    expect(leftResolution.activeSource.sourceStartSeconds, closeTo(0, 0.001));
    expect(leftResolution.activeSource.sourceEndSeconds, closeTo(4, 0.001));
    expect(leftResolution.upcomingSource, isNull);
    expect(rightResolution.upcomingSource, isNull);
  });

  test('delete middle split part leaves non contiguous same-source boundary',
      () {
    final assets = <String, EngineAssetDescriptor>{
      'video-1': asset(
        id: 'video-1',
        uri: '/tmp/video-1.mp4',
        kind: EngineTrackKind.video,
      ),
    };
    final tracks = [
      TimelineTrackData(
        kind: TimelineTrackKind.video,
        clips: [
          clip(
            id: 'video-1_a',
            assetId: 'video-1',
            duration: 1,
            sourceOffsetSeconds: 0,
          ),
          clip(
            id: 'video-1_c',
            assetId: 'video-1',
            duration: 1,
            sourceOffsetSeconds: 2,
          ),
        ],
      ),
    ];

    final resolution = ClipJunctionResolver.resolvePlayback(
      targetNode: node(
        clipId: 'video-1_a',
        assetId: 'video-1',
        kind: EngineTrackKind.video,
        uri: '/tmp/video-1.mp4',
        clipStartSeconds: 0,
        clipEndSeconds: 1,
        sourceStartSeconds: 0,
        sourceEndSeconds: 1,
      ),
      tracks: tracks,
      assetResolver: (assetId) => assets[assetId],
      isPlaying: true,
    );

    expect(resolution, isNotNull);
    expect(
      resolution!.trailingJunction?.kind,
      ClipJunctionKind.sameSourceNonContiguous,
    );
    expect(resolution.activeSource.clipStartSeconds, closeTo(0, 0.001));
    expect(resolution.activeSource.clipEndSeconds, closeTo(1, 0.001));
    expect(resolution.upcomingSource, isNotNull);
    expect(resolution.upcomingSource!.sourceStartSeconds, closeTo(2, 0.001));
    expect(
      resolution.activeSource.effectiveAttachmentId,
      isNot(resolution.upcomingSource!.effectiveAttachmentId),
    );
  });

  test('deleting the left split part preserves the remaining source window',
      () {
    final assets = <String, EngineAssetDescriptor>{
      'video-1': asset(
        id: 'video-1',
        uri: '/tmp/video-1.mp4',
        kind: EngineTrackKind.video,
      ),
    };
    final tracks = [
      TimelineTrackData(
        kind: TimelineTrackKind.video,
        clips: [
          clip(
            id: 'video-1_b',
            assetId: 'video-1',
            duration: 2,
            sourceOffsetSeconds: 2,
          ),
        ],
      ),
    ];

    final resolution = ClipJunctionResolver.resolvePlayback(
      targetNode: node(
        clipId: 'video-1_b',
        assetId: 'video-1',
        kind: EngineTrackKind.video,
        uri: '/tmp/video-1.mp4',
        clipStartSeconds: 0,
        clipEndSeconds: 2,
        sourceStartSeconds: 2,
        sourceEndSeconds: 4,
      ),
      tracks: tracks,
      assetResolver: (assetId) => assets[assetId],
      isPlaying: true,
    );

    expect(resolution, isNotNull);
    expect(resolution!.activeSource.clipStartSeconds, closeTo(0, 0.001));
    expect(resolution.activeSource.clipEndSeconds, closeTo(2, 0.001));
    expect(resolution.activeSource.sourceStartSeconds, closeTo(2, 0.001));
    expect(resolution.activeSource.sourceEndSeconds, closeTo(4, 0.001));
    expect(resolution.upcomingSource, isNull);
  });

  test('video to image boundary is classified explicitly', () {
    final assets = <String, EngineAssetDescriptor>{
      'video-1': asset(
        id: 'video-1',
        uri: '/tmp/video-1.mp4',
        kind: EngineTrackKind.video,
      ),
      'image-1': asset(
        id: 'image-1',
        uri: '/tmp/image-1.jpg',
        kind: EngineTrackKind.image,
        durationSeconds: 2,
      ),
    };
    final tracks = [
      TimelineTrackData(
        kind: TimelineTrackKind.video,
        clips: [
          clip(
            id: 'video-1',
            assetId: 'video-1',
            duration: 1.5,
            sourceOffsetSeconds: 0,
          ),
          clip(
            id: 'image-1',
            assetId: 'image-1',
            duration: 2,
            sourceOffsetSeconds: 0,
          ),
        ],
      ),
    ];

    final resolution = ClipJunctionResolver.resolvePlayback(
      targetNode: node(
        clipId: 'video-1',
        assetId: 'video-1',
        kind: EngineTrackKind.video,
        uri: '/tmp/video-1.mp4',
        clipStartSeconds: 0,
        clipEndSeconds: 1.5,
        sourceStartSeconds: 0,
        sourceEndSeconds: 1.5,
      ),
      tracks: tracks,
      assetResolver: (assetId) => assets[assetId],
      isPlaying: true,
    );

    expect(resolution?.trailingJunction?.kind, ClipJunctionKind.videoToImage);
    expect(resolution?.upcomingSource, isNotNull);
    expect(resolution?.upcomingSource?.localPath, '/tmp/image-1.jpg');
  });

  test('reordered clips resolve upcoming playback from new neighbor order', () {
    final assets = <String, EngineAssetDescriptor>{
      'video-a': asset(
        id: 'video-a',
        uri: '/tmp/video-a.mp4',
        kind: EngineTrackKind.video,
      ),
      'video-b': asset(
        id: 'video-b',
        uri: '/tmp/video-b.mp4',
        kind: EngineTrackKind.video,
      ),
      'video-c': asset(
        id: 'video-c',
        uri: '/tmp/video-c.mp4',
        kind: EngineTrackKind.video,
      ),
    };
    final tracks = [
      TimelineTrackData(
        kind: TimelineTrackKind.video,
        clips: [
          clip(
            id: 'video-a',
            assetId: 'video-a',
            duration: 1,
            sourceOffsetSeconds: 0,
          ),
          clip(
            id: 'video-c',
            assetId: 'video-c',
            duration: 1,
            sourceOffsetSeconds: 0,
          ),
          clip(
            id: 'video-b',
            assetId: 'video-b',
            duration: 1,
            sourceOffsetSeconds: 0,
          ),
        ],
      ),
    ];

    final resolution = ClipJunctionResolver.resolvePlayback(
      targetNode: node(
        clipId: 'video-c',
        assetId: 'video-c',
        kind: EngineTrackKind.video,
        uri: '/tmp/video-c.mp4',
        clipStartSeconds: 1,
        clipEndSeconds: 2,
        sourceStartSeconds: 0,
        sourceEndSeconds: 1,
      ),
      tracks: tracks,
      assetResolver: (assetId) => assets[assetId],
      isPlaying: true,
    );

    expect(resolution, isNotNull);
    expect(resolution!.leadingJunction?.kind, ClipJunctionKind.differentSource);
    expect(resolution.trailingJunction?.kind, ClipJunctionKind.differentSource);
    expect(resolution.upcomingSource?.localPath, '/tmp/video-b.mp4');
  });
}
