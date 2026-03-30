import 'package:flutter_test/flutter_test.dart';

import 'package:fusion_video/core/engine/engine_bridge_stub.dart';
import 'package:fusion_video/core/engine/engine_contract.dart';
import 'package:fusion_video/core/engine/engine_session_controller.dart';
import 'package:fusion_video/features/editor/presentation/models/timeline_mock_models.dart';

void main() {
  const config = EngineProjectConfig(
    width: 1080,
    height: 1920,
    fps: 30,
    sampleRate: 48000,
    durationSeconds: 5,
  );

  Future<void> settleEngine([int milliseconds = 40]) {
    return Future<void>.delayed(Duration(milliseconds: milliseconds));
  }

  FusionVideoEngineSessionController buildController() {
    return FusionVideoEngineSessionController(
      bridge: FusionVideoEngineStub(),
      config: config,
    );
  }

  test('initializes project state and resets cleanly on shutdown', () async {
    final controller = buildController();

    await controller.initialize();
    await settleEngine();

    expect(controller.isReady, isTrue);
    expect(controller.projectHandle, isNotNull);
    expect(controller.selectedClipId, isNull);
    expect(controller.tracks, isEmpty);

    await controller.shutdown();

    expect(controller.isReady, isFalse);
    expect(controller.projectHandle, isNull);
    expect(controller.currentSeconds, 0);
    expect(controller.tracks, isEmpty);

    controller.dispose();
  });

  test('play pause and seek update transport state', () async {
    final controller = buildController();

    await controller.initialize();
    await controller.seekSeconds(1.25);
    await settleEngine();
    expect(controller.currentSeconds, closeTo(1.25, 0.05));

    await controller.play();
    await settleEngine(80);
    expect(controller.isPlaying, isTrue);
    expect(controller.currentSeconds, greaterThan(1.25));

    await controller.pause();
    await settleEngine();
    expect(controller.isPlaying, isFalse);

    await controller.shutdown();
    controller.dispose();
  });

  test('split creates two media clips and clears selection', () async {
    final controller = buildController();

    await controller.initialize();
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-1',
        uri: '/tmp/video-1.mp4',
        kind: EngineTrackKind.video,
        durationSeconds: 3.15,
      ),
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-1',
      assetId: 'video-1',
      durationSeconds: 3.15,
    );
    await controller.seekSeconds(1.4);
    await settleEngine();
    await controller.splitSelectedClip();

    final videoTrack = controller.tracks.first;
    expect(videoTrack.clips, hasLength(2));

    final leftClip = videoTrack.clips[0];
    final rightClip = videoTrack.clips[1];

    expect(leftClip.type, TimelineClipType.media);
    expect(rightClip.type, TimelineClipType.media);
    expect(leftClip.splitGroupId, isNotNull);
    expect(rightClip.splitGroupId, leftClip.splitGroupId);
    expect(leftClip.sourceOffsetSeconds, closeTo(0, 0.001));
    expect(rightClip.sourceOffsetSeconds, closeTo(1.4, 0.1));
    expect(controller.selectedClipId, isNull);

    await controller.shutdown();
    controller.dispose();
  });

  test('split preserves clip order and ignores playhead outside selected clip',
      () async {
    final controller = buildController();

    await controller.initialize();
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-1',
        uri: '/tmp/video-1.mp4',
        kind: EngineTrackKind.video,
        durationSeconds: 3.0,
      ),
    );
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-2',
        uri: '/tmp/video-2.mp4',
        kind: EngineTrackKind.video,
        durationSeconds: 2.0,
      ),
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-1',
      assetId: 'video-1',
      durationSeconds: 3.0,
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-2',
      assetId: 'video-2',
      durationSeconds: 2.0,
    );

    controller.selectClip('video-2');
    await controller.seekSeconds(1.0);
    await settleEngine();
    await controller.splitSelectedClip();

    var ids = controller.tracks.first.clips.map((clip) => clip.id).toList();
    expect(ids, ['video-1', 'video-2']);

    controller.selectClip('video-2');
    await controller.seekSeconds(4.0);
    await settleEngine();
    await controller.splitSelectedClip();

    final clips = controller.tracks.first.clips;
    ids = clips.map((clip) => clip.id).toList();
    expect(ids, ['video-1', 'video-2_a_1', 'video-2_b_1']);
    expect(clips[0].duration, closeTo(3.0, 0.001));
    expect(clips[1].duration + clips[2].duration, closeTo(2.0, 0.001));
    expect(clips[1].sourceOffsetSeconds, closeTo(0.0, 0.001));
    expect(clips[2].sourceOffsetSeconds, closeTo(1.0, 0.001));

    await controller.shutdown();
    controller.dispose();
  });

  test('trim duplicate and delete mutate selected media clip correctly',
      () async {
    final controller = buildController();

    await controller.initialize();
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-1',
        uri: '/tmp/video-1.mp4',
        kind: EngineTrackKind.video,
        durationSeconds: 3.15,
      ),
    );
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-2',
        uri: '/tmp/video-2.mp4',
        kind: EngineTrackKind.video,
        durationSeconds: 0.72,
      ),
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-1',
      assetId: 'video-1',
      durationSeconds: 3.15,
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-2',
      assetId: 'video-2',
      durationSeconds: 0.72,
    );
    controller.selectClip('video-1');

    await controller.seekSeconds(0.9);
    await settleEngine();
    await controller.trimSelectedClipLeft();
    final trimmedLeft = controller.tracks.first.clips.first;
    expect(trimmedLeft.duration, closeTo(2.25, 0.05));

    await controller.seekSeconds(1.5);
    await settleEngine();
    await controller.trimSelectedClipRight();
    final trimmedRight = controller.tracks.first.clips.first;
    expect(trimmedRight.duration, closeTo(1.5, 0.05));

    final beforeDuplicate = controller.tracks.first.clips.length;
    await controller.duplicateSelectedClip();
    expect(controller.tracks.first.clips.length, beforeDuplicate + 1);
    expect(controller.selectedClipId, contains('_copy_'));

    final duplicatedId = controller.selectedClipId;
    await controller.deleteSelectedClip();
    expect(controller.tracks.first.clips.length, beforeDuplicate);
    expect(controller.selectedClipId, isNot(duplicatedId));

    await controller.shutdown();
    controller.dispose();
  });

  test('clip transform persists through split and duplicate snapshots',
      () async {
    final controller = buildController();

    await controller.initialize();
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-1',
        uri: '/tmp/video-1.mp4',
        kind: EngineTrackKind.video,
        durationSeconds: 4.0,
      ),
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-1',
      assetId: 'video-1',
      durationSeconds: 4.0,
    );

    await controller.setClipTransform(
      'video-1',
      const EngineVisualTransformSnapshot(
        x: 120,
        y: 240,
        width: 840,
        height: 1440,
        opacity: 0.9,
        rotationDegrees: 10,
        zIndex: 3,
      ),
    );
    await controller.seekSeconds(1.5);
    await settleEngine();
    await controller.splitSelectedClip();

    var node = await controller.compositionNodeForClipId(
      'video-1_b_1',
      projectSeconds: 2.0,
    );
    expect(node, isNotNull);
    expect(node!.transform.x, closeTo(120, 0.001));
    expect(node.transform.rotationDegrees, closeTo(10, 0.001));

    controller.selectClip('video-1_b_1');
    await controller.duplicateSelectedClip();
    final duplicatedId = controller.selectedClipId;
    expect(duplicatedId, contains('_copy_'));

    node = await controller.compositionNodeForClipId(
      duplicatedId!,
      projectSeconds: 4.25,
    );
    expect(node, isNotNull);
    expect(node!.transform.width, closeTo(840, 0.001));
    expect(node.transform.height, closeTo(1440, 0.001));

    await controller.shutdown();
    controller.dispose();
  });

  test('reorder moves a clip to the previewed insertion slot cleanly',
      () async {
    final controller = buildController();

    await controller.initialize();
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-a',
        uri: '/tmp/video-a.mp4',
        kind: EngineTrackKind.video,
        durationSeconds: 1.2,
      ),
    );
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-b',
        uri: '/tmp/video-b.mp4',
        kind: EngineTrackKind.video,
        durationSeconds: 1.4,
      ),
    );
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-c',
        uri: '/tmp/video-c.mp4',
        kind: EngineTrackKind.video,
        durationSeconds: 1.6,
      ),
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-a',
      assetId: 'video-a',
      durationSeconds: 1.2,
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-b',
      assetId: 'video-b',
      durationSeconds: 1.4,
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-c',
      assetId: 'video-c',
      durationSeconds: 1.6,
    );

    await controller.reorderClipInTrack('video-a', insertionIndex: 2);

    final clipIds = controller.tracks.first.clips
        .map((clip) => clip.id)
        .toList(growable: false);
    expect(clipIds, <String>['video-b', 'video-c', 'video-a']);
    expect(controller.selectedClipId, 'video-a');

    await controller.shutdown();
    controller.dispose();
  });

  test('split delete keeps remaining source order deterministic', () async {
    final controller = buildController();

    await controller.initialize();
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-1',
        uri: '/tmp/video-1.mp4',
        kind: EngineTrackKind.video,
        durationSeconds: 4.0,
      ),
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-1',
      assetId: 'video-1',
      durationSeconds: 4.0,
    );

    await controller.seekSeconds(1.0);
    await settleEngine();
    await controller.splitSelectedClip();

    controller.selectClip(controller.tracks.first.clips[1].id);
    await controller.seekSeconds(2.5);
    await settleEngine();
    await controller.splitSelectedClip();

    final splitClips = controller.tracks.first.clips;
    expect(splitClips, hasLength(3));

    controller.selectClip(splitClips[1].id);
    await controller.deleteSelectedClip();

    final remainingClips = controller.tracks.first.clips;
    expect(remainingClips, hasLength(2));
    expect(remainingClips[0].sourceOffsetSeconds, closeTo(0.0, 0.001));
    expect(remainingClips[0].duration, closeTo(1.0, 0.001));
    expect(remainingClips[1].sourceOffsetSeconds, closeTo(2.5, 0.001));
    expect(remainingClips[1].duration, closeTo(1.5, 0.001));

    await controller.shutdown();
    controller.dispose();
  });

  test('visual binding resolves local media time after split and trim',
      () async {
    final controller = buildController();

    await controller.initialize();
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-1',
        uri: '/tmp/video-1.mp4',
        kind: EngineTrackKind.video,
        durationSeconds: 4,
      ),
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-1',
      assetId: 'video-1',
      durationSeconds: 4,
    );

    await controller.seekSeconds(1.5);
    await settleEngine();
    await controller.splitSelectedClip();

    final rightClipId = controller.tracks.first.clips.last.id;
    await controller.seekSeconds(2.0);
    await settleEngine();

    final binding = controller.visualBindingForClipId(
      rightClipId,
      projectSeconds: controller.currentSeconds,
    );
    expect(binding, isNotNull);
    final resolvedBinding = binding!;
    expect(resolvedBinding.sourceStartSeconds, closeTo(1.5, 0.1));
    expect(resolvedBinding.sourceEndSeconds, closeTo(4.0, 0.1));
    expect(resolvedBinding.sourcePositionSeconds, closeTo(2.0, 0.1));

    await controller.shutdown();
    controller.dispose();
  });

  test('project duration expands to match imported media clip duration',
      () async {
    final controller = buildController();

    await controller.initialize();
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-19',
        uri: '/tmp/video-19.mp4',
        kind: EngineTrackKind.video,
        durationSeconds: 19.0,
      ),
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-19',
      assetId: 'video-19',
      durationSeconds: 19.0,
    );

    expect(controller.durationSeconds, closeTo(19.0, 0.001));

    await controller.shutdown();
    controller.dispose();
  });

  test('composition snapshot resolves visual nodes from engine state',
      () async {
    final controller = buildController();

    await controller.initialize();
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-1',
        uri: '/tmp/video-1.mp4',
        kind: EngineTrackKind.video,
        label: 'video-1.mp4',
        durationSeconds: 4.0,
        width: 1080,
        height: 1920,
      ),
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-1',
      assetId: 'video-1',
      durationSeconds: 4.0,
    );

    final nodes = await controller.compositionAt(1.25);
    expect(nodes, hasLength(1));
    final node = nodes.first;
    expect(node.assetId, 'video-1');
    expect(node.trackKind, EngineTrackKind.video);
    expect(node.displayLabel, 'video-1.mp4');
    expect(node.sourcePositionSeconds, closeTo(1.25, 0.001));
    expect(node.transform.width, closeTo(1080, 0.001));
    expect(node.transform.height, closeTo(1920, 0.001));

    await controller.shutdown();
    controller.dispose();
  });

  test('audio snapshot resolves engine-backed audio nodes', () async {
    final controller = buildController();

    await controller.initialize();
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'audio-1',
        uri: '/tmp/audio-1.m4a',
        kind: EngineTrackKind.audio,
        label: 'audio-1.m4a',
        durationSeconds: 6.0,
      ),
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.audio,
      clipId: 'audio-1',
      assetId: 'audio-1',
      durationSeconds: 6.0,
    );

    await controller.seekSeconds(2.0);
    await settleEngine();
    controller.selectClip('audio-1');
    await controller.splitSelectedClip();

    final nodes = await controller.audioNodesAt(3.5);
    expect(nodes, hasLength(1));
    final node = nodes.first;
    expect(node.assetId, 'audio-1');
    expect(node.displayLabel, 'audio-1.m4a');
    expect(node.sourceStartSeconds, closeTo(2.0, 0.001));
    expect(node.sourcePositionSeconds, closeTo(3.5, 0.001));
    expect(node.sourceEndSeconds, closeTo(6.0, 0.001));

    await controller.shutdown();
    controller.dispose();
  });

  test('video clips also expose audio nodes for mixer foundation', () async {
    final controller = buildController();

    await controller.initialize();
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-audio-1',
        uri: '/tmp/video-audio-1.mp4',
        kind: EngineTrackKind.video,
        label: 'video-audio-1.mp4',
        durationSeconds: 5.0,
      ),
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-audio-1',
      assetId: 'video-audio-1',
      durationSeconds: 5.0,
    );

    final nodes = await controller.audioNodesAt(1.25);
    expect(nodes, hasLength(1));
    final node = nodes.first;
    expect(node.assetId, 'video-audio-1');
    expect(node.trackKind, EngineTrackKind.video);
    expect(node.displayLabel, 'video-audio-1.mp4');
    expect(node.sourcePositionSeconds, closeTo(1.25, 0.001));

    await controller.shutdown();
    controller.dispose();
  });

  test('audio controls flow from engine into audio snapshot', () async {
    final controller = buildController();

    await controller.initialize();
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-audio-1',
        uri: '/tmp/video-audio-1.mp4',
        kind: EngineTrackKind.video,
        label: 'video-audio-1.mp4',
        durationSeconds: 5.0,
        width: 1080,
        height: 1920,
      ),
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-audio-1',
      assetId: 'video-audio-1',
      durationSeconds: 5.0,
    );

    await controller.setSelectedClipGain(0.35);
    await controller.setSelectedClipMuted(true);

    final nodes = await controller.audioNodesAt(1.0);
    expect(nodes, hasLength(1));
    expect(nodes.first.gain, closeTo(0.35, 0.001));
    expect(nodes.first.isMuted, isTrue);

    await controller.shutdown();
    controller.dispose();
  });

  test('deleting the left split segment keeps the remaining source offset',
      () async {
    final controller = buildController();

    await controller.initialize();
    await controller.importAsset(
      const EngineAssetDescriptor(
        id: 'video-1',
        uri: '/tmp/video-1.mp4',
        kind: EngineTrackKind.video,
        durationSeconds: 4.0,
      ),
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-1',
      assetId: 'video-1',
      durationSeconds: 4.0,
    );

    await controller.seekSeconds(2.0);
    await settleEngine();
    await controller.splitSelectedClip();

    final leftClipId = controller.tracks.first.clips.first.id;
    controller.selectClip(leftClipId);
    await controller.deleteSelectedClip();

    final clips = controller.tracks.first.clips;
    expect(clips, hasLength(1));
    expect(clips.first.duration, closeTo(2.0, 0.001));
    expect(clips.first.sourceOffsetSeconds, closeTo(2.0, 0.001));

    final nodes = await controller.compositionAt(0);
    expect(nodes, hasLength(1));
    expect(nodes.first.sourceStartSeconds, closeTo(2.0, 0.001));
    expect(nodes.first.sourcePositionSeconds, closeTo(2.0, 0.001));

    await controller.shutdown();
    controller.dispose();
  });
}
