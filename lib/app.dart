import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/editor/presentation/screens/mobile_editor_screen.dart';

class FxFlutterEditorApp extends StatelessWidget {
  const FxFlutterEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FX Flutter Editor',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: buildFxTheme(),
      darkTheme: buildFxTheme(),
      home: const MobileEditorScreen(),
    );
  }
}
