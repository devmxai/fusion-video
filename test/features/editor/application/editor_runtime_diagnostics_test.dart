import 'package:flutter_test/flutter_test.dart';

import 'package:fusion_video/core/engine/engine_contract.dart';
import 'package:fusion_video/core/preview/preview_backend.dart';
import 'package:fusion_video/features/editor/application/editor_runtime_diagnostics.dart';

void main() {
  test('flags duration mismatch and possible 5s fallback preview', () {
    const diagnosticsSource = PreviewSource(
      id: 'clip-1',
      assetId: 'asset-1',
      kind: PreviewSourceKind.video,
      localPath: '/tmp/a.mp4',
      clipDurationSeconds: 5,
    );

    final diagnostics = EditorRuntimeDiagnostics.capture(
      engineStatus: const EngineStatusSnapshot(
        playbackState: EnginePlaybackState.paused,
        position: EngineTimelinePosition(seconds: 1, frame: 30),
        isBuffering: false,
      ),
      engineDurationSeconds: 9,
      previewState: const PreviewBackendState(
        source: diagnosticsSource,
        isReady: true,
        isPlaying: false,
        positionSeconds: 1,
        durationSeconds: 5,
      ),
      compositionNodes: const <EngineCompositionNodeSnapshot>[],
      audioNodes: const <EngineAudioNodeSnapshot>[],
      selectedClipId: 'clip-1',
    );

    expect(
      diagnostics.warnings,
      contains(
        'Duration mismatch between engine and preview may explain clamp or drift.',
      ),
    );
    expect(
      diagnostics.warnings,
      contains('Possible unresolved 5s fallback duration on preview clip.'),
    );
  });

  test('flags transport mismatch between engine and preview', () {
    final diagnostics = EditorRuntimeDiagnostics.capture(
      engineStatus: const EngineStatusSnapshot(
        playbackState: EnginePlaybackState.paused,
        position: EngineTimelinePosition(seconds: 0.5, frame: 15),
        isBuffering: false,
      ),
      engineDurationSeconds: 4,
      previewState: const PreviewBackendState(
        isReady: true,
        isPlaying: true,
        positionSeconds: 0.5,
        durationSeconds: 4,
      ),
      compositionNodes: const <EngineCompositionNodeSnapshot>[],
      audioNodes: const <EngineAudioNodeSnapshot>[],
    );

    expect(
      diagnostics.warnings,
      contains('Engine and preview transport states are out of sync.'),
    );
  });
}
