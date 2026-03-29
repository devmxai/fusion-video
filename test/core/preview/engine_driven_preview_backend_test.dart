import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fusion_video/core/preview/engine_driven_preview_backend.dart';
import 'package:fusion_video/core/preview/preview_backend.dart';
import 'package:fusion_video/core/preview/preview_session_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const engineChannel = MethodChannel('fusion_video/preview_engine');
  const eventsChannel = MethodChannel('fusion_video/preview_events');

  final recordedCalls = <MethodCall>[];

  setUp(() {
    recordedCalls.clear();
    FusionPreviewSessionBridge.debugOverrideSupportedPlatform = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (call) async {
      recordedCalls.add(call);
      if (call.method == 'isEnginePreviewAvailable') {
        return true;
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventsChannel, (call) async => null);
  });

  tearDown(() {
    FusionPreviewSessionBridge.debugOverrideSupportedPlatform = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventsChannel, null);
  });

  test('resolved payload configures engine preview and updates state',
      () async {
    final backend = EngineDrivenPreviewBackend(projectId: 42);
    const source = PreviewSource(
      id: 'clip-a',
      assetId: 'asset-a',
      kind: PreviewSourceKind.video,
      localPath: '/tmp/video.mp4',
      clipStartSeconds: 1,
      clipEndSeconds: 4,
      sourceStartSeconds: 2,
      sourceEndSeconds: 5,
      clipDurationSeconds: 3,
    );
    const payload = ResolvedPreviewPayload(
      projectId: 42,
      positionSeconds: 2.5,
      isPlaying: false,
      transportRevision: 7,
      source: source,
      upcomingSource: null,
      projectWidth: 1080,
      projectHeight: 1920,
      compositionNodes: <PreviewCompositionNode>[],
      audioNodes: <PreviewAudioNode>[],
      baseClipIds: <String>['clip-a'],
      baseClipId: 'clip-a',
      selectedClipId: 'clip-a',
      baseAudioGain: 1,
      baseAudioMuted: false,
      continuityKind: PreviewContinuityKind.sameSourceContiguous,
    );

    await backend.applyResolvedPayload(payload);

    expect(backend.state.source?.localPath, '/tmp/video.mp4');
    expect(backend.state.positionSeconds, 2.5);
    expect(backend.state.transportRevision, 7);
    expect(backend.state.isFrameReady, isTrue);

    final configureCall = recordedCalls.singleWhere(
      (call) => call.method == 'configurePreviewEngine',
    );
    final args = Map<Object?, Object?>.from(configureCall.arguments as Map);
    expect(args['projectId'], 42);
    expect(args['sourcePath'], '/tmp/video.mp4');
    expect(args['continuityKind'], 'sameSourceContiguous');

    await backend.disposeBackend();
  });

  test('transport commands dispatch through the engine command channel',
      () async {
    final backend = EngineDrivenPreviewBackend(projectId: 7);

    await backend.scrubBegin(1.0);
    await backend.scrubUpdate(1.25);
    await backend.scrubEnd(1.5, isPlaying: false);
    await backend.play();

    final dispatchCalls = recordedCalls
        .where((call) => call.method == 'dispatchPreviewCommand')
        .toList(growable: false);
    expect(dispatchCalls, hasLength(4));

    final kinds = dispatchCalls
        .map(
            (call) => Map<Object?, Object?>.from(call.arguments as Map)['kind'])
        .toList(growable: false);
    expect(
      kinds,
      <Object?>['scrubBegin', 'scrubUpdate', 'scrubEnd', 'play'],
    );

    await backend.disposeBackend();
  });

  test('runtime metrics events update backend state', () async {
    final backend = EngineDrivenPreviewBackend(projectId: 9);

    backend.handleRuntimeEvent(
      const PreviewRuntimeEvent(
        projectId: 9,
        positionSeconds: 4.25,
        isPlaying: true,
        transportRevision: 11,
        isBuffering: true,
        frameReady: true,
        frameDropCount: 3,
        audioDropCount: 1,
        bufferUnderrunCount: 2,
        previewLatencyMillis: 47,
        seekLatencyMillis: 92,
      ),
    );

    expect(backend.state.positionSeconds, 4.25);
    expect(backend.state.isPlaying, isTrue);
    expect(backend.state.isBuffering, isTrue);
    expect(backend.state.isFrameReady, isTrue);
    expect(backend.state.frameDropCount, 3);
    expect(backend.state.audioDropCount, 1);
    expect(backend.state.bufferUnderrunCount, 2);
    expect(backend.state.previewLatencyMillis, 47);
    expect(backend.state.seekLatencyMillis, 92);

    await backend.disposeBackend();
  });
}
