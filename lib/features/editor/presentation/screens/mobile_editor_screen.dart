import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/engine/engine_contract.dart';
import '../../../../core/engine/engine_session_controller.dart';
import '../../../../core/media/local_media_probe.dart';
import '../../../../core/preview/native_preview_backend.dart';
import '../../../../core/preview/preview_backend.dart';
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
  late final FusionPreviewBackend _previewBackend;
  String? _previewAssetId;
  Size? _workspaceSize;
  bool _isSyncingPreviewFromTimeline = false;
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
    _previewBackend = NativePreviewBackend(projectId: 1);
    _engineController.addListener(_handleEngineChanged);
    _previewBackend.addListener(_handlePreviewBackendChanged);
    unawaited(_engineController.initialize());
  }

  MockAssetItem? _findAssetById(String id) {
    for (final asset in _assetLibrary.value) {
      if (asset.id == id) {
        return asset;
      }
    }
    return null;
  }

  MockAssetItem? _assetFromDescriptor(EngineAssetDescriptor descriptor) {
    final existing = _findAssetById(descriptor.id);
    if (existing != null) {
      return existing;
    }
    return MockAssetItem(
      id: descriptor.id,
      tab: switch (descriptor.kind) {
        EngineTrackKind.video => EditorMediaTab.video,
        EngineTrackKind.image => EditorMediaTab.image,
        EngineTrackKind.audio => EditorMediaTab.audio,
        EngineTrackKind.text => EditorMediaTab.text,
        EngineTrackKind.lipSync => EditorMediaTab.lipSync,
        EngineTrackKind.effect => EditorMediaTab.video,
      },
      label: descriptor.uri.split('/').last,
      tone: 80,
      localPath: descriptor.uri,
      isImported: true,
      durationSeconds: descriptor.durationSeconds,
      width: descriptor.width,
      height: descriptor.height,
    );
  }

  Future<EngineVisualBinding?> _currentPreviewBinding({
    double? projectSeconds,
  }) async {
    EngineVisualBinding? targetBinding;
    final selectedClipId = _engineController.selectedClipId;
    final seconds = projectSeconds ?? _engineController.currentSeconds;
    if (selectedClipId != null && !_engineController.isPlaying) {
      targetBinding = _engineController.visualBindingForClipId(
        selectedClipId,
        projectSeconds: seconds,
      );
    }
    targetBinding ??= _engineController.activeVisualBindingAt(seconds);
    return targetBinding;
  }

  Future<void> _syncPreviewFromEngineState() async {
    final targetBinding = await _currentPreviewBinding();

    final currentSource = _previewBackend.state.source;
    if (targetBinding == null) {
      _previewAssetId = null;
      if (currentSource != null) {
        await _previewBackend.attachSource(null);
      }
      return;
    }

    final targetAsset = _assetFromDescriptor(targetBinding.asset);
    if (targetAsset == null || !targetAsset.isVisual) {
      return;
    }

    final targetSource = _previewSourceForBinding(targetBinding);
    if (_shouldAttachPreviewSource(currentSource, targetSource)) {
      await _activatePreviewForAsset(
        targetAsset,
        previewSource: targetSource,
      );
    } else {
      _previewAssetId = targetAsset.id;
    }

    final previewState = _previewBackend.state;
    final localPositionSeconds = targetBinding.sourcePositionSeconds;
    final delta = (localPositionSeconds - previewState.positionSeconds).abs();
    final shouldForce = !_engineController.isPlaying && !_isTimelineScrubbing;
    if (_engineController.isPlaying != previewState.isPlaying ||
        delta > (_engineController.isPlaying ? 0.14 : 0.02) ||
        shouldForce) {
      await _previewBackend.syncTransport(
        positionSeconds: localPositionSeconds,
        isPlaying: _engineController.isPlaying,
        force: shouldForce,
      );
    }
  }

  @override
  void dispose() {
    _engineController.removeListener(_handleEngineChanged);
    _previewBackend.removeListener(_handlePreviewBackendChanged);
    unawaited(_engineController.shutdown());
    _previewSeekDebounce?.cancel();
    unawaited(_previewBackend.disposeBackend());
    _engineController.dispose();
    _assetLibrary.dispose();
    super.dispose();
  }

  void _handleEngineChanged() {
    final handle = _engineController.projectHandle;
    if (handle != null) {
      unawaited(_previewBackend.bindProject(handle.id));
    }
    unawaited(_syncPreviewFromEngineState());
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void _setCurrentSeconds(double value) {
    unawaited(_engineController.seekSeconds(value));
    final previewState = _previewBackend.state;
    if (previewState.isReady && !previewState.isPlaying) {
      unawaited(() async {
        final binding = await _currentPreviewBinding(projectSeconds: value);
        if (binding == null) {
          return;
        }
        _schedulePreviewSeek(
          binding.sourcePositionSeconds,
          immediate: !_isTimelineScrubbing,
        );
      }());
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
    final pending = _pendingPreviewSeekSeconds;
    if (!_previewBackend.state.isReady || pending == null) {
      return;
    }
    _pendingPreviewSeekSeconds = null;
    _previewSeekInFlight = true;
    _isSyncingPreviewFromTimeline = true;
    unawaited(
      _previewBackend
          .syncTransport(
        positionSeconds: pending,
        isPlaying: false,
        force: true,
      )
          .whenComplete(() {
        _previewSeekInFlight = false;
        _isSyncingPreviewFromTimeline = false;
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
    return _engineController.currentSeconds;
  }

  bool get _effectiveIsPlaying {
    return _engineController.isPlaying;
  }

  double get _effectiveTimelineDuration {
    final engineDuration = _engineController.durationSeconds;
    final previewDuration = _previewBackend.state.durationSeconds;
    if (previewDuration <= 0) {
      return engineDuration;
    }
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
    final previewAspect = _previewBackend.state.aspectRatio;
    if (previewAspect != null && previewAspect > 0) {
      return previewAspect;
    }
    return _previewAsset?.aspectRatio;
  }

  Future<void> _togglePlayback() async {
    final previewState = _previewBackend.state;
    if (previewState.isReady) {
      final binding = await _currentPreviewBinding();
      final localSeconds =
          binding?.sourcePositionSeconds ?? previewState.positionSeconds;
      if (previewState.isPlaying) {
        await _engineController.pause();
        await _previewBackend.syncTransport(
          positionSeconds: localSeconds,
          isPlaying: false,
          force: true,
        );
      } else {
        if (previewState.durationSeconds > 0 &&
            previewState.positionSeconds >= previewState.durationSeconds) {
          await _engineController.seekSeconds(0);
        }
        await _engineController.play();
        await _previewBackend.syncTransport(
          positionSeconds: localSeconds,
          isPlaying: true,
          force: true,
        );
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
    final binding = _engineController.visualBindingForClipId(
      clipId,
      projectSeconds: _engineController.currentSeconds,
    );
    final asset = binding == null
        ? _findAssetById(clipId)
        : _assetFromDescriptor(binding.asset);
    if (asset != null && asset.isVisual) {
      unawaited(
        _activatePreviewForAsset(
          asset,
          previewSource:
              binding == null ? null : _previewSourceForBinding(binding),
        ),
      );
    }
  }

  void _handlePreviewBackendChanged() {
    if (!mounted) {
      return;
    }

    final previewState = _previewBackend.state;
    if (previewState.contentSize != null &&
        previewState.contentSize!.width > 0 &&
        previewState.contentSize!.height > 0) {
      _workspaceSize = previewState.contentSize;
    }

    if (!previewState.isPlaying &&
        _engineController.isPlaying &&
        previewState.durationSeconds > 0 &&
        previewState.positionSeconds >= previewState.durationSeconds - 0.04) {
      unawaited(_engineController.pause());
    }

    setState(() {});

    if (_isSyncingPreviewFromTimeline) {
      return;
    }

    final now = DateTime.now();
    if (_lastPreviewSyncAt != null &&
        now.difference(_lastPreviewSyncAt!) <
            const Duration(milliseconds: 80)) {
      return;
    }
    _lastPreviewSyncAt = now;
    unawaited(_engineController.seekSeconds(previewState.positionSeconds));
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
      try {
        final metadata = await _readVideoMetadata(asset.localPath!);
        final updatedAsset = asset.copyWith(
          durationSeconds: metadata.durationSeconds,
          width: metadata.width,
          height: metadata.height,
        );
        _replaceAsset(updatedAsset);
        return updatedAsset;
      } catch (error, stackTrace) {
        debugPrint('Fusion Video: video metadata probe failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        return asset;
      }
    }

    if (asset.tab == EditorMediaTab.image &&
        (asset.width == null || asset.height == null)) {
      try {
        final metadata = await _readImageMetadata(asset.localPath!);
        final updatedAsset = asset.copyWith(
          width: metadata.width,
          height: metadata.height,
        );
        _replaceAsset(updatedAsset);
        return updatedAsset;
      } catch (error, stackTrace) {
        debugPrint('Fusion Video: image metadata probe failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        return asset;
      }
    }

    return asset;
  }

  Future<void> _activatePreviewForAsset(
    MockAssetItem asset, {
    bool autoplay = false,
    PreviewSource? previewSource,
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

    if ((preparedAsset.tab == EditorMediaTab.video ||
            preparedAsset.tab == EditorMediaTab.image) &&
        preparedAsset.localPath != null) {
      await _previewBackend.attachSource(
        previewSource ?? _previewSourceForAsset(preparedAsset),
        autoplay: autoplay,
      );
    } else {
      await _previewBackend.attachSource(null);
    }
    if (mounted) {
      setState(() {});
    }
  }

  PreviewSource _previewSourceForAsset(MockAssetItem asset) {
    return PreviewSource(
      id: asset.id,
      assetId: asset.id,
      kind: asset.tab == EditorMediaTab.video
          ? PreviewSourceKind.video
          : PreviewSourceKind.image,
      localPath: asset.localPath!,
      durationSeconds: asset.durationSeconds,
      width: asset.width,
      height: asset.height,
      sourceStartSeconds: 0,
      sourceEndSeconds: asset.durationSeconds,
      clipDurationSeconds: asset.durationSeconds,
    );
  }

  PreviewSource _previewSourceForBinding(EngineVisualBinding binding) {
    return PreviewSource(
      id: binding.clipId,
      assetId: binding.asset.id,
      kind: binding.asset.kind == EngineTrackKind.video
          ? PreviewSourceKind.video
          : PreviewSourceKind.image,
      localPath: binding.asset.uri,
      durationSeconds: binding.asset.durationSeconds,
      width: binding.asset.width,
      height: binding.asset.height,
      sourceStartSeconds: binding.sourceStartSeconds,
      sourceEndSeconds: binding.sourceEndSeconds,
      clipDurationSeconds: binding.clipDurationSeconds,
    );
  }

  bool _shouldAttachPreviewSource(
    PreviewSource? current,
    PreviewSource target,
  ) {
    if (current == null) {
      return true;
    }

    return current.id != target.id ||
        current.localPath != target.localPath ||
        current.kind != target.kind ||
        (current.sourceStartSeconds - target.sourceStartSeconds).abs() >
            0.001 ||
        ((current.sourceEndSeconds ?? 0) - (target.sourceEndSeconds ?? 0))
                .abs() >
            0.001 ||
        ((current.clipDurationSeconds ?? 0) - (target.clipDurationSeconds ?? 0))
                .abs() >
            0.001;
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
      final handle = _engineController.projectHandle;
      if (handle != null) {
        await _engineController.importAsset(
          EngineAssetDescriptor(
            id: newAsset.id,
            uri: newAsset.localPath ?? '',
            kind: _engineTrackKindFor(newAsset.tab),
            width: newAsset.width,
            height: newAsset.height,
          ),
        );
      }

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

    try {
      final preparedAsset = await _ensureAssetMetadata(asset);
      await _engineController.importAsset(
        EngineAssetDescriptor(
          id: preparedAsset.id,
          uri: preparedAsset.localPath ?? '',
          kind: _engineTrackKindFor(preparedAsset.tab),
          durationSeconds: preparedAsset.durationSeconds,
          width: preparedAsset.width,
          height: preparedAsset.height,
        ),
      );
      final durationSeconds = preparedAsset.durationSeconds ??
          _defaultDurationFor(preparedAsset.tab);
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
        assetId: preparedAsset.id,
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
    } catch (error, stackTrace) {
      debugPrint('Fusion Video: add asset to timeline failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Add to timeline failed: $error'),
          duration: const Duration(milliseconds: 2200),
        ),
      );
    }
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
    final metadata = await probeVideoMetadata(path);
    return _ImportedAssetMetadata(
      durationSeconds: metadata.durationSeconds,
      width: metadata.width,
      height: metadata.height,
    );
  }

  Future<_ImportedAssetMetadata> _readImageMetadata(String path) async {
    final metadata = await probeImageMetadata(path);
    return _ImportedAssetMetadata(
      width: metadata.width,
      height: metadata.height,
    );
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
                        child: _previewBackend.buildView(),
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
