import 'package:flutter_test/flutter_test.dart';

import 'package:fusion_video/app.dart';

void main() {
  testWidgets('renders mobile editor shell', (WidgetTester tester) async {
    await tester.pumpWidget(const FxFlutterEditorApp());

    expect(find.text('Video'), findsWidgets);
    expect(find.text('Lip Sync'), findsOneWidget);
  });
}
