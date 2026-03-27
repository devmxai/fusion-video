import 'editor_media_tab.dart';

class MockAssetItem {
  const MockAssetItem({
    required this.id,
    required this.tab,
    required this.label,
    required this.tone,
  });

  final String id;
  final EditorMediaTab tab;
  final String label;
  final int tone;
}
