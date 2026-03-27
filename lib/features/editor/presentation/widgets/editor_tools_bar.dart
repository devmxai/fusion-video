import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'fx_icon_button.dart';

class EditorToolsBar extends StatelessWidget {
  const EditorToolsBar({
    super.key,
    this.embedded = false,
    this.isPlaying = false,
    this.onSplit,
    this.onPlayToggle,
  });

  final bool embedded;
  final bool isPlaying;
  final VoidCallback? onSplit;
  final VoidCallback? onPlayToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: embedded ? Colors.transparent : FxPalette.surface,
        borderRadius: BorderRadius.circular(embedded ? 0 : 16),
        border:
            embedded ? null : Border.all(color: FxPalette.divider, width: 1),
      ),
      child: Row(
        children: [
          FxIconButton(
            icon: Icons.cut_rounded,
            size: 30,
            iconScale: 0.4,
            onPressed: onSplit,
          ),
          const SizedBox(width: 5),
          const FxIconButton(
            icon: Icons.keyboard_tab_rounded,
            size: 30,
            iconScale: 0.4,
          ),
          const SizedBox(width: 5),
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(3.14159),
            child: const FxIconButton(
              icon: Icons.keyboard_tab_rounded,
              size: 30,
              iconScale: 0.4,
            ),
          ),
          const SizedBox(width: 5),
          const FxIconButton(
            icon: Icons.delete_outline_rounded,
            size: 30,
            iconScale: 0.4,
          ),
          const Spacer(),
          FxIconButton(
            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 32,
            iconScale: 0.48,
            foregroundColor: FxPalette.textPrimary,
            onPressed: onPlayToggle,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
