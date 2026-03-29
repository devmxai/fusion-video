import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'preview_backend.dart';

class FusionPreviewSessionBridge {
  FusionPreviewSessionBridge._();

  static bool? debugOverrideSupportedPlatform;

  static const MethodChannel _channel =
      MethodChannel('fusion_video/preview_session');
  static const MethodChannel _engineChannel =
      MethodChannel('fusion_video/preview_engine');
  static const EventChannel _eventsChannel =
      EventChannel('fusion_video/preview_events');

  static bool get _isSupportedRuntime {
    if (kIsWeb) {
      return false;
    }
    return debugOverrideSupportedPlatform ??
        (Platform.isIOS || Platform.isAndroid);
  }

  static Future<void> updatePreview({
    required int projectId,
    required double positionSeconds,
    required bool isPlaying,
    int? transportRevision,
    String? sourceId,
    String? sourcePath,
    String? sourceKind,
    String? upcomingSourceId,
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
    List<String>? baseClipIds,
    String? selectedClipId,
    double? baseAudioGain,
    bool? baseAudioMuted,
    List<Map<String, dynamic>>? sceneNodes,
    List<Map<String, dynamic>>? audioNodes,
  }) async {
    if (!_isSupportedRuntime) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('updatePreview', <String, dynamic>{
        'projectId': projectId,
        'positionSeconds': positionSeconds,
        'isPlaying': isPlaying,
        'transportRevision': transportRevision,
        'sourceId': sourceId,
        'sourcePath': sourcePath,
        'sourceKind': sourceKind,
        'upcomingSourceId': upcomingSourceId,
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
        'baseClipIds': baseClipIds,
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

  static Future<bool> isEnginePreviewAvailable() async {
    if (!_isSupportedRuntime) {
      return false;
    }
    try {
      return await _engineChannel.invokeMethod<bool>(
            'isEnginePreviewAvailable',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> configurePreviewEngine(
    ResolvedPreviewPayload payload,
  ) async {
    if (!_isSupportedRuntime) {
      return;
    }

    try {
      await _engineChannel.invokeMethod<void>(
        'configurePreviewEngine',
        payload.toMap(),
      );
    } on MissingPluginException {
      // Engine preview bridge is not registered on this platform/runtime yet.
    }
  }

  static Future<void> dispatchPreviewCommand({
    required int projectId,
    required int transportRevision,
    required PreviewTransportCommand command,
  }) async {
    if (!_isSupportedRuntime) {
      return;
    }

    try {
      await _engineChannel.invokeMethod<void>(
        'dispatchPreviewCommand',
        <String, dynamic>{
          'projectId': projectId,
          'transportRevision': transportRevision,
          ...command.toMap(),
        },
      );
    } on MissingPluginException {
      // Engine preview bridge is not registered on this platform/runtime yet.
    }
  }

  static Stream<PreviewRuntimeEvent> watchPreviewEvents(int projectId) {
    if (!_isSupportedRuntime) {
      return const Stream<PreviewRuntimeEvent>.empty();
    }

    return _eventsChannel.receiveBroadcastStream(<String, dynamic>{
      'projectId': projectId,
    }).map((dynamic event) {
      final map = Map<dynamic, dynamic>.from(event as Map);
      return PreviewRuntimeEvent(
        projectId: (map['projectId'] as num?)?.toInt() ?? projectId,
        positionSeconds: (map['positionSeconds'] as num?)?.toDouble() ?? 0,
        isPlaying: map['isPlaying'] as bool? ?? false,
        transportRevision: (map['transportRevision'] as num?)?.toInt() ?? 0,
        isBuffering: map['isBuffering'] as bool? ?? false,
        frameReady: map['frameReady'] as bool? ?? false,
      );
    });
  }
}
