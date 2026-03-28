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

  test('split creates two media clips and selects the right segment', () async {
    final controller = buildController();

    await controller.initialize();
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-1',
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
    expect(controller.selectedClipId, rightClip.id);

    await controller.shutdown();
    controller.dispose();
  });

  test('trim duplicate and delete mutate selected media clip correctly',
      () async {
    final controller = buildController();

    await controller.initialize();
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-1',
      durationSeconds: 3.15,
    );
    await controller.insertClip(
      trackKind: EngineTrackKind.video,
      clipId: 'video-2',
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
}
