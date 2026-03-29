import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../../../core/media/device_media_library.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/editor_media_tab.dart';

class VisualMediaBottomSheet extends StatefulWidget {
  const VisualMediaBottomSheet({
    super.key,
    required this.initialTab,
    required this.onImportSelection,
  });

  final EditorMediaTab initialTab;
  final Future<void> Function(
    EditorMediaTab tab,
    List<DeviceMediaAsset> assets,
  ) onImportSelection;

  @override
  State<VisualMediaBottomSheet> createState() => _VisualMediaBottomSheetState();
}

class _VisualMediaBottomSheetState extends State<VisualMediaBottomSheet> {
  static const double _initialSheetSize = 0.65;
  static const int _crossAxisCount = 3;

  EditorMediaTab _activeTab = EditorMediaTab.video;
  List<DeviceMediaAsset> _items = const <DeviceMediaAsset>[];
  final Set<String> _selectedIds = <String>{};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isImporting = false;
  bool _hasMore = true;
  bool _hasAccess = true;
  bool _isLimited = false;
  int _page = 0;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab == EditorMediaTab.image
        ? EditorMediaTab.image
        : EditorMediaTab.video;
    _reload();
  }

  Future<void> _reload() async {
    final serial = ++_requestSerial;
    setState(() {
      _items = const <DeviceMediaAsset>[];
      _selectedIds.clear();
      _page = 0;
      _hasMore = true;
      _isLoading = true;
      _isLoadingMore = false;
    });

    final page = await DeviceMediaLibrary.loadPage(
      tab: _activeTab,
      page: 0,
    );

    if (!mounted || serial != _requestSerial) {
      return;
    }

    setState(() {
      _hasAccess = page.access.hasAccess;
      _isLimited = page.access.isLimited;
      _items = page.items;
      _hasMore = page.hasMore;
      _isLoading = false;
      _page = 1;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore || !_hasAccess) {
      return;
    }

    final serial = _requestSerial;
    setState(() => _isLoadingMore = true);
    final page = await DeviceMediaLibrary.loadPage(
      tab: _activeTab,
      page: _page,
    );
    if (!mounted || serial != _requestSerial) {
      return;
    }

    setState(() {
      _hasAccess = page.access.hasAccess;
      _isLimited = page.access.isLimited;
      _items = [..._items, ...page.items];
      _hasMore = page.hasMore;
      _isLoadingMore = false;
      _page += 1;
    });
  }

  bool _handleGridScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 480) {
      _loadMore();
    }
    return false;
  }

  void _toggleSelection(DeviceMediaAsset asset) {
    setState(() {
      if (_selectedIds.contains(asset.id)) {
        _selectedIds.remove(asset.id);
      } else {
        _selectedIds.add(asset.id);
      }
    });
  }

  Future<void> _handleImport() async {
    if (_selectedIds.isEmpty || _isImporting) {
      return;
    }

    final selectedAssets = _items
        .where((asset) => _selectedIds.contains(asset.id))
        .toList(growable: false);
    setState(() => _isImporting = true);
    try {
      await widget.onImportSelection(_activeTab, selectedAssets);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  String _formatDuration(DeviceMediaAsset asset) {
    final seconds = asset.durationSeconds?.round() ?? 0;
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }

  Widget _buildTab(EditorMediaTab tab) {
    final isActive = tab == _activeTab;
    return Expanded(
      child: GestureDetector(
        onTap: isActive
            ? null
            : () {
                setState(() => _activeTab = tab);
                _reload();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive
                    ? Colors.white.withOpacity(0.82)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
          ),
          child: Text(
            tab.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? FxPalette.textPrimary : FxPalette.textMuted,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Allow photo access to browse your studio here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: FxPalette.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isLimited
                  ? 'Only selected media are visible right now.'
                  : 'Without permission, videos and images cannot appear in this sheet.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: FxPalette.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: DeviceMediaLibrary.openSettings,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                minimumSize: const Size(132, 44),
              ),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          _activeTab == EditorMediaTab.video
              ? 'No videos found in your studio.'
              : 'No images found in your studio.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: FxPalette.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildGrid() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (!_hasAccess) {
      return _buildPermissionState();
    }
    if (_items.isEmpty) {
      return _buildEmptyState();
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleGridScroll,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _crossAxisCount,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.78,
        ),
        itemCount: _items.length + (_isLoadingMore ? 3 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final asset = _items[index];
          final isSelected = _selectedIds.contains(asset.id);
          return GestureDetector(
            onTap: () => _toggleSelection(asset),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? Colors.white.withOpacity(0.4)
                      : Colors.white.withOpacity(0.06),
                  width: isSelected ? 1.4 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.22),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AssetEntityImage(
                      asset.entity,
                      isOriginal: false,
                      thumbnailSize: const ThumbnailSize.square(420),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.low,
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.05),
                            Colors.transparent,
                            Colors.black.withOpacity(0.28),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white
                              : Colors.black.withOpacity(0.36),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? Colors.white
                                : Colors.white.withOpacity(0.12),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          isSelected ? Icons.check_rounded : Icons.add_rounded,
                          size: 16,
                          color: isSelected ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                    if (asset.tab == EditorMediaTab.video)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.48),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _formatDuration(asset),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: _initialSheetSize,
      minChildSize: 0.5,
      maxChildSize: 0.92,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  children: [
                    _buildTab(EditorMediaTab.video),
                    _buildTab(EditorMediaTab.image),
                  ],
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: FxPalette.dividerSoft.withOpacity(0.92),
              ),
              Expanded(
                child: PrimaryScrollController(
                  controller: controller,
                  child: _buildGrid(),
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  decoration: BoxDecoration(
                    color: FxPalette.panel.withOpacity(0.98),
                    border: Border(
                      top: BorderSide(
                        color: FxPalette.dividerSoft.withOpacity(0.92),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _selectedIds.isEmpty
                            ? 'Select media'
                            : '${_selectedIds.length} selected',
                        style: const TextStyle(
                          color: FxPalette.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _selectedIds.isEmpty || _isImporting
                            ? null
                            : _handleImport,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor:
                              Colors.white.withOpacity(0.12),
                          disabledForegroundColor:
                              FxPalette.textMuted.withOpacity(0.8),
                          minimumSize: const Size(116, 44),
                        ),
                        child: _isImporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Text(
                                'Import',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
