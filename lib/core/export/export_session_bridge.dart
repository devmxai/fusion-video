import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'export_backend.dart';

class FusionExportSessionBridge {
  FusionExportSessionBridge._();

  static const MethodChannel _channel =
      MethodChannel('fusion_video/export_session');

  static Future<FusionExportStatus> startExport(
    FusionExportRequest request,
  ) async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) {
      throw UnsupportedError('Native export is unavailable on this platform.');
    }

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'startExport',
      request.toMap(),
    );
    if (result == null) {
      throw StateError('Native export did not return a job.');
    }
    return _parseStatus(result);
  }

  static Future<FusionExportStatus> pollStatus(String jobId) async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) {
      return const FusionExportStatus(
        kind: FusionExportStatusKind.failed,
        errorMessage: 'Native export is unavailable on this platform.',
      );
    }

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pollExport',
      <String, dynamic>{'jobId': jobId},
    );
    if (result == null) {
      throw StateError('Native export did not return status.');
    }
    return _parseStatus(result);
  }

  static Future<void> cancelExport(String jobId) async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) {
      return;
    }

    await _channel.invokeMethod<void>(
      'cancelExport',
      <String, dynamic>{'jobId': jobId},
    );
  }

  static FusionExportStatus _parseStatus(Map<String, dynamic> map) {
    final statusValue = map['status'] as String? ?? 'failed';
    final kind = switch (statusValue) {
      'idle' => FusionExportStatusKind.idle,
      'exporting' => FusionExportStatusKind.exporting,
      'completed' => FusionExportStatusKind.completed,
      'cancelled' => FusionExportStatusKind.cancelled,
      _ => FusionExportStatusKind.failed,
    };
    return FusionExportStatus(
      kind: kind,
      jobId: map['jobId'] as String?,
      progress: ((map['progress'] as num?) ?? 0).toDouble(),
      outputPath: map['outputPath'] as String?,
      errorMessage: map['errorMessage'] as String?,
    );
  }
}
