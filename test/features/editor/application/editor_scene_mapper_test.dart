import 'package:flutter_test/flutter_test.dart';

import 'package:fusion_video/core/engine/engine_contract.dart';
import 'package:fusion_video/core/preview/preview_backend.dart';
import 'package:fusion_video/features/editor/application/editor_scene_mapper.dart';

void main() {
  EngineVisualTransformSnapshot buildTransform({int zIndex = 0}) {
    return EngineVisualTransformSnapshot(
      x: 0,
      y: 0,
      width: 1080,
      height: 1920,
      opacity: 1,
      rotationDegrees: 0,
      zIndex: zIndex,
    );
  }

  EngineCompositionNodeSnapshot buildNode({
    required String clipId,
    required String assetId,
    required EngineTrackKind kind,
    int zIndex = 0,
  }) {
    return EngineCompositionNodeSnapshot(
      clipId: clipId,
      assetId: assetId,
      trackKind: kind,
      assetUri: '/tmp/$assetId',
      clipStartSeconds: 0,
      clipEndSeconds: 4,
      clipDurationSeconds: 4,
      sourceStartSeconds: 0,
      sourceEndSeconds: 4,
      sourcePositionSeconds: 1,
      transform: buildTransform(zIndex: zIndex),
    );
  }

  test('prefers selected visual node while paused', () {
    final base = buildNode(
      clipId: 'base-clip',
      assetId: 'base-asset',
      kind: EngineTrackKind.video,
      zIndex: 0,
    );
    final overlay = buildNode(
      clipId: 'overlay-clip',
      assetId: 'overlay-asset',
      kind: EngineTrackKind.image,
      zIndex: 10,
    );

    final resolved = EditorSceneMapper.resolveBasePreviewNode(
      [base, overlay],
      isPlaying: false,
      selectedClipId: 'overlay-clip',
    );

    expect(resolved?.clipId, 'overlay-clip');
  });

  test('reattaches preview source when source bounds change', () {
    const current = PreviewSource(
      id: 'clip-1',
      assetId: 'asset-1',
      kind: PreviewSourceKind.video,
      localPath: '/tmp/a.mp4',
      sourceStartSeconds: 0,
      sourceEndSeconds: 4,
      clipDurationSeconds: 4,
    );
    const target = PreviewSource(
      id: 'clip-1',
      assetId: 'asset-1',
      kind: PreviewSourceKind.video,
      localPath: '/tmp/a.mp4',
      sourceStartSeconds: 1.25,
      sourceEndSeconds: 4,
      clipDurationSeconds: 2.75,
    );

    final shouldAttach = EditorSceneMapper.shouldAttachPreviewSource(
      current,
      target,
    );

    expect(shouldAttach, isTrue);
  });
}
