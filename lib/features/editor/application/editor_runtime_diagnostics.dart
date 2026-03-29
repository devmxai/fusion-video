import '../../../core/engine/engine_contract.dart';
import '../../../core/preview/preview_backend.dart';

class EditorRuntimeDiagnostics {
  const EditorRuntimeDiagnostics({
    required this.enginePlaybackState,
    required this.previewIsReady,
    required this.previewIsPlaying,
    required this.enginePositionSeconds,
    required this.engineDurationSeconds,
    required this.previewPositionSeconds,
    required this.previewDurationSeconds,
    required this.selectedClipId,
    required this.previewSourceId,
    required this.previewSourceKind,
    required this.compositionNodeCount,
    required this.audioNodeCount,
    required this.warnings,
  });

  final EnginePlaybackState enginePlaybackState;
  final bool previewIsReady;
  final bool previewIsPlaying;
  final double enginePositionSeconds;
  final double engineDurationSeconds;
  final double previewPositionSeconds;
  final double previewDurationSeconds;
  final String? selectedClipId;
  final String? previewSourceId;
  final String? previewSourceKind;
  final int compositionNodeCount;
  final int audioNodeCount;
  final List<String> warnings;

  bool get hasWarnings => warnings.isNotEmpty;

  static EditorRuntimeDiagnostics capture({
    required EngineStatusSnapshot engineStatus,
    required double engineDurationSeconds,
    required PreviewBackendState previewState,
    required List<EngineCompositionNodeSnapshot> compositionNodes,
    required List<EngineAudioNodeSnapshot> audioNodes,
    String? selectedClipId,
  }) {
    final warnings = <String>[];
    final engineIsPlaying =
        engineStatus.playbackState == EnginePlaybackState.playing;
    final previewSource = previewState.source;

    if (previewState.isReady &&
        previewState.isPlaying != engineIsPlaying &&
        !(previewState.isPlaying == false &&
            engineStatus.playbackState == EnginePlaybackState.scrubbing)) {
      warnings.add('Engine and preview transport states are out of sync.');
    }

    if (previewState.isReady &&
        previewState.durationSeconds > 0 &&
        engineDurationSeconds > 0 &&
        (previewState.durationSeconds - engineDurationSeconds).abs() > 0.5) {
      warnings.add(
        'Duration mismatch between engine and preview may explain clamp or drift.',
      );
    }

    if (selectedClipId != null &&
        compositionNodes.isNotEmpty &&
        compositionNodes.every((node) => node.clipId != selectedClipId)) {
      warnings.add('Selected clip is outside the current visual scene.');
    }

    if (previewSource != null &&
        compositionNodes.isNotEmpty &&
        compositionNodes.every((node) => node.clipId != previewSource.id)) {
      warnings.add('Current preview source does not match the active scene.');
    }

    if (previewSource != null &&
        previewSource.durationSeconds == null &&
        ((previewSource.clipDurationSeconds ?? 0) - 5).abs() < 0.001 &&
        previewSource.kind == PreviewSourceKind.video) {
      warnings.add('Possible unresolved 5s fallback duration on preview clip.');
    }

    if (audioNodes.any(
      (node) => node.sourceEndSeconds <= node.sourceStartSeconds,
    )) {
      warnings.add('Audio node bounds are invalid for the current playhead.');
    }

    return EditorRuntimeDiagnostics(
      enginePlaybackState: engineStatus.playbackState,
      previewIsReady: previewState.isReady,
      previewIsPlaying: previewState.isPlaying,
      enginePositionSeconds: engineStatus.position.seconds,
      engineDurationSeconds: engineDurationSeconds,
      previewPositionSeconds: previewState.positionSeconds,
      previewDurationSeconds: previewState.durationSeconds,
      selectedClipId: selectedClipId,
      previewSourceId: previewSource?.id,
      previewSourceKind: previewSource?.kind.name,
      compositionNodeCount: compositionNodes.length,
      audioNodeCount: audioNodes.length,
      warnings: List.unmodifiable(warnings),
    );
  }
}
