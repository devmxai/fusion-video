import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/engine/engine_contract.dart';
import '../../../../core/theme/app_theme.dart';

class CompositionPreviewOverlay extends StatelessWidget {
  const CompositionPreviewOverlay({
    super.key,
    required this.nodes,
    required this.projectWidth,
    required this.projectHeight,
    this.baseClipId,
    this.selectedClipId,
  });

  final List<EngineCompositionNodeSnapshot> nodes;
  final int projectWidth;
  final int projectHeight;
  final String? baseClipId;
  final String? selectedClipId;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty || projectWidth <= 0 || projectHeight <= 0) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widthScale = constraints.maxWidth / projectWidth;
          final heightScale = constraints.maxHeight / projectHeight;

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (final node in nodes)
                if (node.clipId != baseClipId &&
                    node.transform.width > 0 &&
                    node.transform.height > 0)
                  Positioned(
                    left: node.transform.x * widthScale,
                    top: node.transform.y * heightScale,
                    width: node.transform.width * widthScale,
                    height: node.transform.height * heightScale,
                    child: Opacity(
                      opacity: node.transform.opacity.clamp(0.0, 1.0),
                      child: Transform.rotate(
                        angle: node.transform.rotationDegrees *
                            3.1415926535 /
                            180.0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: node.clipId == selectedClipId
                                  ? FxPalette.accent
                                  : Colors.white.withOpacity(0.14),
                              width: node.clipId == selectedClipId ? 2 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: _OverlayContent(node: node),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _OverlayContent extends StatelessWidget {
  const _OverlayContent({required this.node});

  final EngineCompositionNodeSnapshot node;

  @override
  Widget build(BuildContext context) {
    switch (node.trackKind) {
      case EngineTrackKind.image:
        final file = File(node.assetUri);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(
              icon: Icons.image_rounded,
              label: 'Image',
            ),
          );
        }
        return _placeholder(icon: Icons.image_rounded, label: 'Image');
      case EngineTrackKind.text:
        return _placeholder(icon: Icons.text_fields_rounded, label: 'Text');
      case EngineTrackKind.lipSync:
        return _placeholder(icon: Icons.graphic_eq_rounded, label: 'Lip Sync');
      case EngineTrackKind.video:
        return _placeholder(icon: Icons.videocam_rounded, label: 'Video');
      case EngineTrackKind.audio:
      case EngineTrackKind.effect:
        return const SizedBox.shrink();
    }
  }

  Widget _placeholder({
    required IconData icon,
    required String label,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            FxPalette.surfaceRaised.withOpacity(0.9),
            FxPalette.surface.withOpacity(0.92),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white.withOpacity(0.86), size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.86),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
