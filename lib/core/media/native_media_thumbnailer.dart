import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeMediaThumbnailer {
  NativeMediaThumbnailer._();

  static const MethodChannel _channel =
      MethodChannel('fusion_video/media_probe');

  static Future<List<Uint8List>> generateVideoThumbnails({
    required String path,
    required List<double> timestampsSeconds,
    int targetWidth = 80,
    int targetHeight = 48,
  }) async {
    if (timestampsSeconds.isEmpty ||
        kIsWeb ||
        !(Platform.isIOS || Platform.isAndroid)) {
      return const <Uint8List>[];
    }

    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'generateVideoThumbnails',
        <String, dynamic>{
          'path': path,
          'timestampsSeconds': timestampsSeconds,
          'targetWidth': targetWidth,
          'targetHeight': targetHeight,
        },
      );
      if (result == null) {
        return const <Uint8List>[];
      }
      return result.whereType<Uint8List>().toList(growable: false);
    } on MissingPluginException {
      return const <Uint8List>[];
    }
  }
}
