import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

import '../../features/editor/presentation/models/editor_media_tab.dart';

class DeviceMediaAccessSnapshot {
  const DeviceMediaAccessSnapshot({
    required this.hasAccess,
    required this.isLimited,
  });

  final bool hasAccess;
  final bool isLimited;
}

class DeviceMediaAsset {
  const DeviceMediaAsset({
    required this.entity,
    required this.tab,
  });

  final AssetEntity entity;
  final EditorMediaTab tab;

  String get id => entity.id;
  int get width => entity.width;
  int get height => entity.height;
  double? get durationSeconds =>
      tab == EditorMediaTab.video ? entity.duration.toDouble() : null;
}

class DeviceMediaPage {
  const DeviceMediaPage({
    required this.access,
    required this.items,
    required this.hasMore,
  });

  final DeviceMediaAccessSnapshot access;
  final List<DeviceMediaAsset> items;
  final bool hasMore;
}

class DeviceMediaLibrary {
  const DeviceMediaLibrary._();

  static const int defaultPageSize = 60;

  static Future<DeviceMediaAccessSnapshot> requestAccess() async {
    final status = await PhotoManager.requestPermissionExtend();
    return DeviceMediaAccessSnapshot(
      hasAccess: status.hasAccess,
      isLimited: status.isLimited,
    );
  }

  static Future<DeviceMediaPage> loadPage({
    required EditorMediaTab tab,
    required int page,
    int pageSize = defaultPageSize,
  }) async {
    final access = await requestAccess();
    if (!access.hasAccess) {
      return DeviceMediaPage(
        access: access,
        items: const <DeviceMediaAsset>[],
        hasMore: false,
      );
    }

    final requestType = switch (tab) {
      EditorMediaTab.video => RequestType.video,
      EditorMediaTab.image => RequestType.image,
      _ => RequestType.common,
    };

    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: requestType,
      filterOption: FilterOptionGroup(
        orders: const <OrderOption>[
          OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );

    if (paths.isEmpty) {
      return DeviceMediaPage(
        access: access,
        items: const <DeviceMediaAsset>[],
        hasMore: false,
      );
    }

    final path = paths.first;
    final totalCount = await path.assetCountAsync;
    final entities = await path.getAssetListPaged(page: page, size: pageSize);
    final items = entities
        .where(
          (entity) => switch (tab) {
            EditorMediaTab.video => entity.type == AssetType.video,
            EditorMediaTab.image => entity.type == AssetType.image,
            _ => false,
          },
        )
        .map((entity) => DeviceMediaAsset(entity: entity, tab: tab))
        .toList(growable: false);

    final loadedCount = ((page + 1) * pageSize).clamp(0, totalCount);

    return DeviceMediaPage(
      access: access,
      items: items,
      hasMore: loadedCount < totalCount,
    );
  }

  static Future<File?> loadOriginFile(DeviceMediaAsset asset) async {
    final originFile = await asset.entity.originFile;
    if (originFile != null) {
      return originFile;
    }
    return asset.entity.file;
  }

  static Future<String> resolveTitle(DeviceMediaAsset asset) async {
    final inline = asset.entity.title;
    if (inline != null && inline.trim().isNotEmpty) {
      return inline.trim();
    }
    final asyncTitle = await asset.entity.titleAsync;
    if (asyncTitle.trim().isNotEmpty) {
      return asyncTitle.trim();
    }
    return '${asset.tab.name}_${asset.entity.id}';
  }

  static Future<void> openSettings() async {
    await PhotoManager.openSetting();
  }
}
