import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/engine/engine_contract.dart';
import '../../../../core/engine/engine_session_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/editor_media_tab.dart';
import '../models/mock_asset_item.dart';
import '../models/timeline_mock_models.dart';
import '../widgets/editor_tools_bar.dart';
import '../widgets/editor_top_bar.dart';
import '../widgets/media_bottom_sheet.dart';
import '../widgets/media_dock.dart';
import '../widgets/preview_stage.dart';
import '../widgets/timeline_panel.dart';

class MobileEditorScreen extends StatefulWidget {
  const MobileEditorScreen({super.key});

  @override
  State<MobileEditorScreen> createState() => _MobileEditorScreenState();
}

class _MobileEditorScreenState extends State<MobileEditorScreen> {
  static const double _timelineDuration = 5;
  final ImagePicker _imagePicker = ImagePicker();

  EditorMediaTab activeTab = EditorMediaTab.video;
  late final FusionVideoEngineSessionController _engineController;
  late final ValueNotifier<List<MockAssetItem>> _assetLibrary;
  VideoPlayerController? _previewVideoController;
  String? _previewAssetId;
  Size? _workspaceSize;
  bool _isSyncingVideoFromTimeline = false;
  bool _isTimelineScrubbing = false;
  DateTime? _lastPreviewSyncAt;
  Timer? _previewSeekDebounce;
  double? _pendingPreviewSeekSeconds;
  bool _previewSeekInFlight = false;

  @override
  void initState() {
    super.initState();
    _engineController = FusionVideoEngineSessionController(
      config: const EngineProjectConfig(
        width: 1080,
        height: 1920,
        fps: 30,
        sampleRate: 48000,
        durationSeconds: _timelineDuration,
      ),
    );
    _assetLibrary = ValueNotifier<List<MockAssetItem>>(
      const <MockAssetItem>[],
    );
    _engineController.addListener(_handleEngineChanged);
    unawaited(_engineController.initialize());
  }

  @override
  void dispose() {
    _engineController.removeListener(_handleEngineChanged);
    unawaited(_engineController.shutdown());
    _previewSeekDebounce?.cancel();
    _previewVideoController?.removeListener(_handlePreviewVideoChanged);
    unawaited(_previewVideoController?.dispose() ?? Future<void>.value());
    _engineController.dispose();
    _assetLibrary.dispose();
    super.dispose();
  }

  void _handleEngineChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void _setCurrentSeconds(double value) {
    unawaited(_engineController.seekSeconds(value));
    final controller = _previewVideoController;
    if (controller != null &&
        controller.value.isInitialized &&
        !controller.value.isPlaying) {
      _schedulePreviewSeek(value, immediate: !_isTimelineScrubbing);
    }
  }

  void _schedulePreviewSeek(double seconds, {bool immediate = false}) {
    _pendingPreviewSeekSeconds = seconds;
    if (immediate) {
      _flushPreviewSeek();
      return;
    }
    _previewSeekDebounce ??= Timer(
      Duration(milliseconds: _isTimelineScrubbing ? 48 : 16),
      _flushPreviewSeek,
    );
  }

  void _flushPreviewSeek() {
    _previewSeekDebounce?.cancel();
    _previewSeekDebounce = null;
    if (_previewSeekInFlight) {
      return;
    }
    final controller = _previewVideoController;
    final pending = _pendingPreviewSeekSeconds;
    if (controller == null ||
        !controller.value.isInitialized ||
        pending == null) {
      return;
    }
    _pendingPreviewSeekSeconds = null;
    _previewSeekInFlight = true;
    _isSyncingVideoFromTimeline = true;
    unawaited(
      controller
          .seekTo(Duration(milliseconds: (pending * 1000).round()))
          .whenComplete(() {
        _previewSeekInFlight = false;
        _isSyncingVideoFromTimeline = false;
        if (_pendingPreviewSeekSeconds != null) {
          _previewSeekDebounce =
              Timer(const Duration(milliseconds: 16), _flushPreviewSeek);
        }
        if (mounted) {
          setState(() {});
        }
      }),
    );
  }

  double get _effectiveCurrentSeconds {
    final controller = _previewVideoController;
    if (controller != null && controller.value.isInitialized) {
      return controller.value.position.inMicroseconds /
          Duration.microsecondsPerSecond;
    }
    return _engineController.currentSeconds;
  }

  bool get _effectiveIsPlaying {
    final controller = _previewVideoController;
    if (controller != null && controller.value.isInitialized) {
      return controller.value.isPlaying;
    }
    return _engineController.isPlaying;
  }

  double get _effectiveTimelineDuration {
    final controller = _previewVideoController;
    final engineDuration = _engineController.durationSeconds;
    if (controller == null || !controller.value.isInitialized) {
      return engineDuration;
    }
    final previewDuration = controller.value.duration.inMicroseconds /
        Duration.microsecondsPerSecond;
    return previewDuration > engineDuration ? previewDuration : engineDuration;
  }

  MockAssetItem? get _previewAsset {
    final previewAssetId = _previewAssetId;
    if (previewAssetId == null) {
      return null;
    }
    for (final asset in _assetLibrary.value) {
      if (asset.id == previewAssetId) {
        return asset;
      }
    }
    return null;
  }

  double? get _workspaceAspectRatio {
    final size = _workspaceSize;
    if (size != null && size.height > 0) {
      return size.width / size.height;
    }
    return _previewAsset?.aspectRatio;
  }

  Future<void> _togglePlayback() async {
    final controller = _previewVideoController;
    if (controller != null && controller.value.isInitialized) {
      if (controller.value.isPlaying) {
        await controller.pause();
        await _engineController.pause();
      } else {
        if (controller.value.position >= controller.value.duration &&
            controller.value.duration > Duration.zero) {
          await controller.seekTo(Duration.zero);
          await _engineController.seekSeconds(0);
        }
        await controller.play();
        await _engineController.play();
      }
      if (mounted) {
        setState(() {});
      }
      return;
    }
    await _engineController.togglePlayback();
  }

  Future<void> _syncCurrentTimeBeforeEdit(
      Future<void> Function() action) async {
    await _engineController.seekSeconds(_effectiveCurrentSeconds);
    await action();
  }

  void _handleClipSelected(String clipId) {
    _engineController.selectClip(clipId);
    MockAssetItem? asset;
    for (final item in _assetLibrary.value) {
      if (item.id == clipId) {
        asset = item;
        break;
      }
    }
    if (asset != null && asset.isVisual) {
      unawaited(_activatePreviewForAsset(asset));
    }
  }

  void _handlePreviewVideoChanged() {
    final controller = _previewVideoController;
    if (!mounted || controller == null || !controller.value.isInitialized) {
      return;
    }

    if (!controller.value.isPlaying &&
        _engineController.isPlaying &&
        controller.value.duration > Duration.zero &&
        controller.value.position >=
            controller.value.duration - const Duration(milliseconds: 40)) {
      unawaited(_engineController.pause());
    }

    setState(() {});

    if (_isSyncingVideoFromTimeline) {
      return;
    }

    final now = DateTime.now();
    if (_lastPreviewSyncAt != null &&
        now.difference(_lastPreviewSyncAt!) <
            const Duration(milliseconds: 80)) {
      return;
    }
    _lastPreviewSyncAt = now;
    unawaited(_engineController.seekSeconds(_effectiveCurrentSeconds));
  }

  void _handleTimelineScrubStateChanged(bool isActive) {
    if (_isTimelineScrubbing == isActive) {
      return;
    }
    _isTimelineScrubbing = isActive;
    if (!isActive) {
      _flushPreviewSeek();
    }
  }

  void _replaceAsset(MockAssetItem updatedAsset) {
    final nextAssets = _assetLibrary.value
        .map((item) => item.id == updatedAsset.id ? updatedAsset : item)
        .toList(growable: false);
    _assetLibrary.value = nextAssets;
  }

  Future<MockAssetItem> _ensureAssetMetadata(MockAssetItem asset) async {
    if (asset.localPath == null) {
      return asset;
    }

    if (asset.tab == EditorMediaTab.video &&
        (asset.durationSeconds == null ||
            asset.width == null ||
            asset.height == null)) {
      final metadata = await _readVideoMetadata(asset.localPath!);
      final updatedAsset = asset.copyWith(
        durationSeconds: metadata.durationSeconds,
        width: metadata.width,
        height: metadata.height,
      );
      _replaceAsset(updatedAsset);
      return updatedAsset;
    }

    if (asset.tab == EditorMediaTab.image &&
        (asset.width == null || asset.height == null)) {
      final metadata = await _readImageMetadata(asset.localPath!);
      final updatedAsset = asset.copyWith(
        width: metadata.width,
        height: metadata.height,
      );
      _replaceAsset(updatedAsset);
      return updatedAsset;
    }

    return asset;
  }

  Future<void> _activatePreviewForAsset(
    MockAssetItem asset, {
    bool autoplay = false,
  }) async {
    if (!asset.isVisual) {
      return;
    }

    _previewAssetId = asset.id;
    var preparedAsset = asset;
    if ((asset.width == null || asset.height == null) &&
        asset.localPath != null) {
      preparedAsset = await _ensureAssetMetadata(asset);
    }
    if (preparedAsset.width != null && preparedAsset.height != null) {
      _workspaceSize = Size(
        preparedAsset.width!.toDouble(),
        preparedAsset.height!.toDouble(),
      );
    }

    if (preparedAsset.tab == EditorMediaTab.video &&
        preparedAsset.localPath != null) {
      final previousController = _previewVideoController;
      previousController?.removeListener(_handlePreviewVideoChanged);
      await previousController?.dispose();

      final controller =
          VideoPlayerController.file(File(preparedAsset.localPath!));
      await controller.initialize();
      await controller.setLooping(false);
      final videoSize = controller.value.size;
      if (videoSize.width > 0 && videoSize.height > 0) {
        _workspaceSize = Size(videoSize.width, videoSize.height);
      }
      controller.addListener(_handlePreviewVideoChanged);
      _previewVideoController = controller;
      if (autoplay) {
        await controller.play();
      }
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final previousController = _previewVideoController;
    previousController?.removeListener(_handlePreviewVideoChanged);
    await previousController?.dispose();
    _previewVideoController = null;
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildPreviewContent() {
    final asset = _previewAsset;
    if (asset == null) {
      return const SizedBox.expand();
    }

    if (asset.tab == EditorMediaTab.video) {
      final controller = _previewVideoController;
      if (controller == null || !controller.value.isInitialized) {
        return const SizedBox.expand();
      }

      final videoSize = controller.value.size;
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: videoSize.width,
            height: videoSize.height,
            child: VideoPlayer(controller),
          ),
        ),
      );
    }

    if (asset.tab == EditorMediaTab.image && asset.localPath != null) {
      return SizedBox.expand(
        child: Image.file(
          File(asset.localPath!),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.expand(),
        ),
      );
    }

    return const SizedBox.expand();
  }

  Future<void> _openMediaSheet(EditorMediaTab tab) async {
    setState(() => activeTab = tab);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.52),
      isScrollControlled: true,
      builder: (context) {
        return MediaBottomSheet(
          activeTab: activeTab,
          assetsListenable: _assetLibrary,
          onImportTap: _importAssetForTab,
          onAssetAdd: _addAssetToTimeline,
        );
      },
    );
  }

  Future<void> _importAssetForTab(EditorMediaTab tab) async {
    try {
      if (tab == EditorMediaTab.text || tab == EditorMediaTab.lipSync) {
        final label =
            tab == EditorMediaTab.text ? 'Text Layer' : 'Lip Sync Layer';
        final newAsset = MockAssetItem(
          id: '${tab.name}_${DateTime.now().microsecondsSinceEpoch}',
          tab: tab,
          label: label,
          tone: 40 + (_assetLibrary.value.length * 37) % 300,
        );
        _assetLibrary.value = [..._assetLibrary.value, newAsset];
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label created'),
            duration: const Duration(milliseconds: 1000),
          ),
        );
        return;
      }

      final importedFile = await _pickAssetForTab(tab);
      if (importedFile == null) {
        return;
      }

      final id = '${tab.name}_${DateTime.now().microsecondsSinceEpoch}';
      final newAsset = MockAssetItem(
        id: id,
        tab: tab,
        label: importedFile.name,
        tone: 40 + (_assetLibrary.value.length * 37) % 300,
        localPath: importedFile.path,
        isImported: true,
        width: importedFile.width,
        height: importedFile.height,
      );

      _assetLibrary.value = [..._assetLibrary.value, newAsset];

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${importedFile.name} imported successfully'),
          duration: const Duration(milliseconds: 1200),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import failed: $error'),
          duration: const Duration(milliseconds: 2200),
        ),
      );
    }
  }

  Future<_ImportedAssetFile?> _pickAssetForTab(EditorMediaTab tab) async {
    switch (tab) {
      case EditorMediaTab.video:
        final file = await _imagePicker.pickVideo(
          source: ImageSource.gallery,
        );
        if (file == null) {
          return null;
        }
        return _ImportedAssetFile(
          path: file.path,
          name: file.name,
        );
      case EditorMediaTab.image:
        final file = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          requestFullMetadata: false,
        );
        if (file == null) {
          return null;
        }
        final metadata = await _readImageMetadata(file.path);
        return _ImportedAssetFile(
          path: file.path,
          name: file.name,
          width: metadata.width,
          height: metadata.height,
        );
      case EditorMediaTab.audio:
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: false,
          type: FileType.custom,
          allowedExtensions: _allowedExtensionsFor(tab),
        );
        if (result == null || result.files.isEmpty) {
          return null;
        }
        final file = result.files.single;
        if (file.path == null) {
          return null;
        }
        return _ImportedAssetFile(
          path: file.path!,
          name: file.name,
        );
      case EditorMediaTab.text:
      case EditorMediaTab.lipSync:
        return null;
    }
  }

  Future<void> _addAssetToTimeline(MockAssetItem asset) async {
    final handle = _engineController.projectHandle;
    if (handle == null) {
      return;
    }

    final preparedAsset = await _ensureAssetMetadata(asset);
    final durationSeconds =
        preparedAsset.durationSeconds ?? _defaultDurationFor(preparedAsset.tab);
    final trackKind = _engineTrackKindFor(preparedAsset.tab);
    final hadVisualTracks = _engineController.tracks.any(
      (track) =>
          (track.kind == TimelineTrackKind.video ||
              track.kind == TimelineTrackKind.image) &&
          track.clips.isNotEmpty,
    );

    await _engineController.insertClip(
      trackKind: trackKind,
      clipId: preparedAsset.id,
      durationSeconds: durationSeconds,
      isMedia: true,
    );

    if (preparedAsset.isVisual) {
      if (!hadVisualTracks &&
          preparedAsset.width != null &&
          preparedAsset.height != null) {
        _workspaceSize = Size(
          preparedAsset.width!.toDouble(),
          preparedAsset.height!.toDouble(),
        );
      }
      await _activatePreviewForAsset(preparedAsset);
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${preparedAsset.label} added to timeline'),
        duration: const Duration(milliseconds: 1000),
      ),
    );
  }

  EngineTrackKind _engineTrackKindFor(EditorMediaTab tab) {
    switch (tab) {
      case EditorMediaTab.video:
        return EngineTrackKind.video;
      case EditorMediaTab.image:
        return EngineTrackKind.image;
      case EditorMediaTab.audio:
        return EngineTrackKind.audio;
      case EditorMediaTab.text:
        return EngineTrackKind.text;
      case EditorMediaTab.lipSync:
        return EngineTrackKind.lipSync;
    }
  }

  double _defaultDurationFor(EditorMediaTab tab) {
    switch (tab) {
      case EditorMediaTab.video:
        return 5;
      case EditorMediaTab.image:
        return 3;
      case EditorMediaTab.audio:
        return 5;
      case EditorMediaTab.text:
        return 3;
      case EditorMediaTab.lipSync:
        return 3;
    }
  }

  List<String> _allowedExtensionsFor(EditorMediaTab tab) {
    switch (tab) {
      case EditorMediaTab.video:
        return const ['mp4', 'mov', 'm4v'];
      case EditorMediaTab.image:
        return const ['png', 'jpg', 'jpeg', 'webp', 'heic'];
      case EditorMediaTab.audio:
        return const ['mp3', 'wav', 'm4a', 'aac', 'ogg'];
      case EditorMediaTab.text:
        return const ['txt'];
      case EditorMediaTab.lipSync:
        return const ['png', 'jpg', 'jpeg'];
    }
  }

  Future<_ImportedAssetMetadata> _readVideoMetadata(String path) async {
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      final value = controller.value;
      return _ImportedAssetMetadata(
        durationSeconds:
            value.duration.inMicroseconds / Duration.microsecondsPerSecond,
        width: value.size.width.round(),
        height: value.size.height.round(),
      );
    } finally {
      await controller.dispose();
    }
  }

  Future<_ImportedAssetMetadata> _readImageMetadata(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final metadata = _ImportedAssetMetadata(
      width: frame.image.width,
      height: frame.image.height,
    );
    frame.image.dispose();
    codec.dispose();
    return metadata;
  }

  @override
  Widget build(BuildContext context) {
    final currentSeconds = _effectiveCurrentSeconds;
    final isPlaying = _effectiveIsPlaying;
    final tracks = _engineController.tracks;
    final selectedClipId = _engineController.selectedClipId;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              color: FxPalette.background,
              child: Column(
                children: [
                  const EditorTopBar(),
                  Expanded(
                    flex: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 220),
                      child: PreviewStage(
                        workspaceAspectRatio: _workspaceAspectRatio,
                        child: _buildPreviewContent(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    flex: 4,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(2, 0, 2, 4),
                      decoration: BoxDecoration(
                        color: FxPalette.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: FxPalette.divider,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 3),
                            child: EditorToolsBar(
                              embedded: true,
                              isPlaying: isPlaying,
                              onSplit: () => _syncCurrentTimeBeforeEdit(
                                _engineController.splitSelectedClip,
                              ),
                              onTrimRight: () => _syncCurrentTimeBeforeEdit(
                                _engineController.trimSelectedClipRight,
                              ),
                              onTrimLeft: () => _syncCurrentTimeBeforeEdit(
                                _engineController.trimSelectedClipLeft,
                              ),
                              onDuplicate:
                                  _engineController.duplicateSelectedClip,
                              onDelete: _engineController.deleteSelectedClip,
                              onPlayToggle: _togglePlayback,
                            ),
                          ),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: FxPalette.dividerSoft.withOpacity(0.9),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 2, 0, 0),
                              child: TimelinePanel(
                                embedded: true,
                                tracks: tracks,
                                currentSeconds: currentSeconds,
                                timelineDuration: _effectiveTimelineDuration,
                                isPlaying: isPlaying,
                                selectedClipId: selectedClipId,
                                onTimeChanged: _setCurrentSeconds,
                                onClipSelected: _handleClipSelected,
                                onScrubStateChanged:
                                    _handleTimelineScrubStateChanged,
                              ),
                            ),
                          ),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: FxPalette.dividerSoft.withOpacity(0.9),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
                            child: MediaDock(
                              activeTab: activeTab,
                              onTap: _openMediaSheet,
                              embedded: true,
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
        ),
      ),
    );
  }
}

class _ImportedAssetFile {
  const _ImportedAssetFile({
    required this.path,
    required this.name,
    this.width,
    this.height,
  });

  final String path;
  final String name;
  final int? width;
  final int? height;
}

class _ImportedAssetMetadata {
  const _ImportedAssetMetadata({
    this.durationSeconds,
    this.width,
    this.height,
  });

  final double? durationSeconds;
  final int? width;
  final int? height;
}
