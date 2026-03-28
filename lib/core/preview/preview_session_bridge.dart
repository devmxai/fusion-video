import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FusionPreviewSessionBridge {
  FusionPreviewSessionBridge._();

  static const MethodChannel _channel =
      MethodChannel('fusion_video/preview_session');

  static Future<void> updatePreview({
    required int projectId,
    required double positionSeconds,
    required bool isPlaying,
    String? sourcePath,
    String? sourceKind,
    double? sourceStartSeconds,
    double? sourceEndSeconds,
  }) async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('updatePreview', <String, dynamic>{
        'projectId': projectId,
        'positionSeconds': positionSeconds,
        'isPlaying': isPlaying,
        'sourcePath': sourcePath,
        'sourceKind': sourceKind,
        'sourceStartSeconds': sourceStartSeconds,
        'sourceEndSeconds': sourceEndSeconds,
      });
    } on MissingPluginException {
      // Preview bridge is not registered on this platform/runtime yet.
    }
  }
}
