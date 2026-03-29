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
    String? upcomingSourcePath,
    String? upcomingSourceKind,
    double? clipStartSeconds,
    double? clipEndSeconds,
    double? sourceStartSeconds,
    double? sourceEndSeconds,
    double? upcomingSourceStartSeconds,
    double? upcomingSourceEndSeconds,
    int? projectWidth,
    int? projectHeight,
    String? baseClipId,
    String? selectedClipId,
    double? baseAudioGain,
    bool? baseAudioMuted,
    List<Map<String, dynamic>>? sceneNodes,
    List<Map<String, dynamic>>? audioNodes,
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
        'upcomingSourcePath': upcomingSourcePath,
        'upcomingSourceKind': upcomingSourceKind,
        'clipStartSeconds': clipStartSeconds,
        'clipEndSeconds': clipEndSeconds,
        'sourceStartSeconds': sourceStartSeconds,
        'sourceEndSeconds': sourceEndSeconds,
        'upcomingSourceStartSeconds': upcomingSourceStartSeconds,
        'upcomingSourceEndSeconds': upcomingSourceEndSeconds,
        'projectWidth': projectWidth,
        'projectHeight': projectHeight,
        'baseClipId': baseClipId,
        'selectedClipId': selectedClipId,
        'baseAudioGain': baseAudioGain,
        'baseAudioMuted': baseAudioMuted,
        'sceneNodes': sceneNodes,
        'audioNodes': audioNodes,
      });
    } on MissingPluginException {
      // Preview bridge is not registered on this platform/runtime yet.
    }
  }
}
