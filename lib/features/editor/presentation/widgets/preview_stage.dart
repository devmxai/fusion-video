import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class PreviewStage extends StatelessWidget {
  const PreviewStage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final frameHeight = constraints.maxHeight;
        final frameWidth = frameHeight * 9 / 16;

        return Container(
          color: FxPalette.background,
          alignment: Alignment.center,
          child: SizedBox(
            width: frameWidth.clamp(0, constraints.maxWidth),
            height: frameHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          FxPalette.previewTop,
                          FxPalette.previewBottom,
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.03),
                            Colors.transparent,
                            Colors.black.withOpacity(0.34),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.only(top: 18),
                      child: Text(
                        'FX Preview',
                        style: TextStyle(
                          color: FxPalette.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 24,
                    top: 82,
                    child: Container(
                      width: 98,
                      height: 98,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.025),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.09),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    bottom: 34,
                    right: 18,
                    child: Container(
                      height: 98,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.03),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
