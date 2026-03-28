import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeMediaProbe {
  NativeMediaProbe._();

  static const MethodChannel _channel =
      MethodChannel('fusion_video/media_probe');

  static Future<Map<String, dynamic>?> probe({
    required String path,
    required String kind,
  }) async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) {
      return null;
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'probeMedia',
        <String, dynamic>{
          'path': path,
          'kind': kind,
        },
      );
      if (result == null) {
        return null;
      }
      return Map<String, dynamic>.from(result);
    } on MissingPluginException {
      return null;
    }
  }
}
