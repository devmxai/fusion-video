import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FusionPreviewSurface extends StatelessWidget {
  const FusionPreviewSurface({
    super.key,
    required this.projectId,
  });

  final int projectId;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) {
      return const _PreviewFallbackSurface();
    }

    final creationParams = <String, dynamic>{
      'projectId': projectId,
    };

    if (Platform.isIOS) {
      return UiKitView(
        viewType: 'fusion_video/preview_surface',
        layoutDirection: TextDirection.ltr,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    return AndroidView(
      viewType: 'fusion_video/preview_surface',
      layoutDirection: TextDirection.ltr,
      creationParams: creationParams,
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}

class _PreviewFallbackSurface extends StatelessWidget {
  const _PreviewFallbackSurface();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF101010),
      alignment: Alignment.center,
      child: Text(
        'Fusion Preview',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
