import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'fx_icon_button.dart';

class EditorTopBar extends StatelessWidget {
  const EditorTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        color: FxPalette.background,
        border: Border(
          bottom: BorderSide(color: FxPalette.divider, width: 1),
        ),
      ),
      child: const Row(
        children: [
          FxIconButton(icon: Icons.history_rounded, size: 34, iconScale: 0.38),
          SizedBox(width: 6),
          FxIconButton(icon: Icons.undo_rounded, size: 34, iconScale: 0.38),
          SizedBox(width: 6),
          FxIconButton(icon: Icons.redo_rounded, size: 34, iconScale: 0.38),
          Spacer(),
          FxIconButton(
              icon: Icons.ios_share_rounded, size: 34, iconScale: 0.38),
        ],
      ),
    );
  }
}
