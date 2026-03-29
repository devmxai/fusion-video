import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fusion_video/core/preview/native_preview_backend.dart';
import 'package:fusion_video/core/preview/preview_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('fusion_video/preview_session');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('scene updates preserve last transport revision while playing', () async {
    final backend = NativePreviewBackend(projectId: 7);
    const source = PreviewSource(
      id: 'clip-a',
      assetId: 'asset-a',
      kind: PreviewSourceKind.video,
      localPath: '/tmp/video.mp4',
      clipStartSeconds: 0,
      clipEndSeconds: 4,
      sourceStartSeconds: 0,
      sourceEndSeconds: 4,
      clipDurationSeconds: 4,
    );

    await backend.attachSource(source);
    await backend.syncTransport(
      positionSeconds: 1.25,
      isPlaying: true,
      force: true,
    );
    final transportRevision = backend.state.transportRevision;
    final positionSeconds = backend.state.positionSeconds;

    await backend.updateCompositionScene(
      projectWidth: 1080,
      projectHeight: 1920,
      nodes: const <PreviewCompositionNode>[],
      audioNodes: const <PreviewAudioNode>[],
      baseClipId: 'clip-a',
    );

    expect(backend.state.transportRevision, transportRevision);
    expect(backend.state.positionSeconds, positionSeconds);
  });
}
