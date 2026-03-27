import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../models/editor_media_tab.dart';
import '../models/mock_asset_item.dart';

class MediaBottomSheet extends StatelessWidget {
  const MediaBottomSheet({
    super.key,
    required this.activeTab,
    required this.assets,
  });

  final EditorMediaTab activeTab;
  final List<MockAssetItem> assets;

  @override
  Widget build(BuildContext context) {
    final filtered = assets.where((item) => item.tab == activeTab).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.44,
      minChildSize: 0.32,
      maxChildSize: 0.84,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: FxPalette.panel,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: FxPalette.divider, width: 1),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Text(
                      activeTab.label,
                      style: const TextStyle(
                        color: FxPalette.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.92,
                  ),
                  itemCount: filtered.length + 1,
                  itemBuilder: (context, index) {
                    if (index == filtered.length) {
                      return Container(
                        decoration: BoxDecoration(
                          color: FxPalette.surface,
                          borderRadius: BorderRadius.circular(18),
                          border:
                              Border.all(color: FxPalette.divider, width: 1),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.add_rounded,
                            color: FxPalette.textPrimary,
                            size: 36,
                          ),
                        ),
                      );
                    }

                    final item = filtered[index];
                    final isEven = index.isEven;
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: FxPalette.divider, width: 1),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            isEven
                                ? FxPalette.surfaceRaised
                                : FxPalette.surface,
                            isEven ? FxPalette.surface : FxPalette.panel,
                          ],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 10,
                            child: Text(
                              item.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: FxPalette.textPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: const BoxDecoration(
                                color: FxPalette.accent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.add_rounded,
                                color: Colors.black,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
