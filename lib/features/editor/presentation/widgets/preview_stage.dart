import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class PreviewStage extends StatelessWidget {
  const PreviewStage({
    super.key,
    required this.workspaceAspectRatio,
    required this.child,
  });

  final double? workspaceAspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspectRatio =
            (workspaceAspectRatio != null && workspaceAspectRatio! > 0)
                ? workspaceAspectRatio!
                : 9 / 16;

        var targetWidth = constraints.maxWidth;
        var targetHeight = targetWidth / aspectRatio;

        if (targetHeight > constraints.maxHeight) {
          targetHeight = constraints.maxHeight;
          targetWidth = targetHeight * aspectRatio;
        }

        return ColoredBox(
          color: FxPalette.background,
          child: Center(
            child: SizedBox(
              width: targetWidth,
              height: targetHeight,
              child: ColoredBox(
                color: Colors.black,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
