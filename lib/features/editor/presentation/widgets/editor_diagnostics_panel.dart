import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/editor_runtime_diagnostics.dart';

class EditorDiagnosticsPanel extends StatelessWidget {
  const EditorDiagnosticsPanel({
    super.key,
    required this.diagnostics,
  });

  final EditorRuntimeDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      color: FxPalette.textMuted,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );
    const valueStyle = TextStyle(
      color: FxPalette.textPrimary,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: FxPalette.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FxPalette.divider, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _MetricLine(
                label: 'Engine',
                value:
                    '${_formatSeconds(diagnostics.enginePositionSeconds)} / ${_formatSeconds(diagnostics.engineDurationSeconds)}',
              ),
              _MetricLine(
                label: 'Preview',
                value:
                    '${_formatSeconds(diagnostics.previewPositionSeconds)} / ${_formatSeconds(diagnostics.previewDurationSeconds)}',
              ),
              _MetricLine(
                label: 'State',
                value:
                    '${diagnostics.enginePlaybackState.name} | preview ${diagnostics.previewIsReady ? (diagnostics.previewIsPlaying ? 'playing' : 'paused') : 'idle'}${diagnostics.previewIsBuffering ? ' | buffering' : ''}${diagnostics.previewFrameReady ? ' | frame ready' : ''}',
              ),
              _MetricLine(
                label: 'Source',
                value:
                    '${diagnostics.previewSourceKind ?? 'none'}:${diagnostics.previewSourceId ?? 'none'}',
              ),
              _MetricLine(
                label: 'Latency',
                value:
                    '${diagnostics.previewLatencyMillis.toStringAsFixed(0)}ms preview | ${diagnostics.seekLatencyMillis.toStringAsFixed(0)}ms seek',
              ),
              _MetricLine(
                label: 'Drops',
                value:
                    '${diagnostics.frameDropCount} frame | ${diagnostics.audioDropCount} audio | ${diagnostics.bufferUnderrunCount} underrun',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Scene ${diagnostics.compositionNodeCount} visual | ${diagnostics.audioNodeCount} audio | selected ${diagnostics.selectedClipId ?? 'none'}',
            style: valueStyle,
          ),
          if (diagnostics.hasWarnings) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final warning in diagnostics.warnings)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: FxPalette.danger.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: FxPalette.danger.withOpacity(0.45),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      warning,
                      style: labelStyle.copyWith(color: FxPalette.textPrimary),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatSeconds(double value) {
    final clamped = value < 0 ? 0.0 : value;
    final totalMilliseconds = (clamped * 1000).round();
    final minutes = (totalMilliseconds ~/ 60000).toString().padLeft(2, '0');
    final seconds =
        ((totalMilliseconds % 60000) ~/ 1000).toString().padLeft(2, '0');
    final milliseconds = (totalMilliseconds % 1000).toString().padLeft(3, '0');
    return '$minutes:$seconds.$milliseconds';
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: FxPalette.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(
              color: FxPalette.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}
