import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../application/editor_media_support.dart';
import '../../application/editor_runtime_diagnostics.dart';
import '../../application/editor_scene_mapper.dart';
import '../../../../core/engine/engine_contract.dart';
import '../../../../core/engine/engine_session_controller.dart';
import '../../../../core/export/export_backend.dart';
import '../../../../core/export/export_session_controller.dart';
import '../../../../core/export/native_export_backend.dart';
import '../../../../core/preview/native_preview_backend.dart';
import '../../../../core/preview/preview_backend.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/editor_media_tab.dart';
import '../models/mock_asset_item.dart';
import '../models/timeline_mock_models.dart';
import '../widgets/editor_diagnostics_panel.dart';
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
  static const double _initialProjectDuration = 0;
  final ImagePicker _imagePicker = ImagePicker();

  EditorMediaTab activeTab = EditorMediaTab.video;
  late final FusionVideoEngineSessionController _engineController;
  late final ValueNotifier<List<MockAssetItem>> _assetLibrary;
  late final FusionPreviewBackend _previewBackend;
  late final FusionExportSessionController _exportController;
  List<EngineCompositionNodeSnapshot> _compositionNodes =
      const <EngineCompositionNodeSnapshot>[];
  List<EngineAudioNodeSnapshot> _audioNodes = const <EngineAudioNodeSnapshot>[];
  String? _previewAssetId;
  Size? _workspaceSize;
  bool _isTimelineScrubbing = false;
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
        durationSeconds: _initialProjectDuration,
      ),
    );
    _assetLibrary = ValueNotifier<List<MockAssetItem>>(
      const <MockAssetItem>[],
    );
    _previewBackend = NativePreviewBackend(projectId: 1);
    _exportController = FusionExportSessionController(
      backend: NativeExportBackend(),
    );
    _engineController.addListener(_handleEngineChanged);
    _previewBackend.addListener(_handlePreviewBackendChanged);
    _exportController.addListener(_handleExportChanged);
    unawaited(_engineController.initialize());
    unawaited(_exportController.initialize());
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
      label: descriptor.label ?? descriptor.uri.split('/').last,
      tone: 80,
      localPath: descriptor.uri,
      isImported: true,
      durationSeconds: descriptor.durationSeconds,
      width: descriptor.width,
      height: descriptor.height,
    );
  }

  Future<EngineCompositionNodeSnapshot?> _currentPreviewNode({
    double? projectSeconds,
  }) async {
    final seconds = projectSeconds ?? _engineController.currentSeconds;
    final nodes = await _engineController.compositionAt(seconds);
    _compositionNodes = nodes;
    return EditorSceneMapper.resolveBasePreviewNode(
      nodes,
      isPlaying: _engineController.isPlaying,
      selectedClipId: _engineController.selectedClipId,
    );
  }

  Future<void> _syncPreviewFromEngineState() async {
    final targetNode = await _currentPreviewNode();
    _audioNodes = await _engineController.audioNodesAt(
      _engineController.currentSeconds,
    );
    EngineAudioNodeSnapshot? baseAudioNode;
    final targetClipId = targetNode?.clipId;
    if (targetClipId != null) {
      for (final node in _audioNodes) {
        if (node.clipId == targetClipId &&
            node.trackKind == EngineTrackKind.video) {
          baseAudioNode = node;
          break;
        }
      }
    }
    await _previewBackend.updateCompositionScene(
      projectWidth: _engineController.projectWidth,
      projectHeight: _engineController.projectHeight,
      nodes: EditorSceneMapper.previewCompositionNodes(
        _compositionNodes,
        assetLabelResolver: (assetId) => _findAssetById(assetId)?.label,
      ),
      audioNodes: EditorSceneMapper.previewAudioNodes(_audioNodes),
      baseClipId: targetNode?.clipId,
      selectedClipId: _engineController.selectedClipId,
      baseAudioGain: baseAudioNode?.gain ?? 1,
      baseAudioMuted: baseAudioNode?.isMuted ?? false,
    );

    final currentSource = _previewBackend.state.source;
    if (targetNode == null) {
      _compositionNodes = const <EngineCompositionNodeSnapshot>[];
      _previewAssetId = null;
      if (currentSource != null) {
        await _previewBackend.attachSource(null);
      }
      return;
    }

    final targetDescriptor = _engineController.assetForId(targetNode.assetId) ??
        EngineAssetDescriptor(
          id: targetNode.assetId,
          uri: targetNode.assetUri,
          kind: targetNode.trackKind,
          label: targetNode.displayLabel,
        );
    final targetAsset = _assetFromDescriptor(targetDescriptor);
    if (targetAsset == null || !targetAsset.isVisual) {
      return;
    }

    final targetSource = _previewSourceForNode(targetNode);
    final didAttachSource = EditorSceneMapper.shouldAttachPreviewSource(
      currentSource,
      targetSource,
    );
    if (didAttachSource) {
      await _activatePreviewForAsset(
        targetAsset,
        previewSource: targetSource,
      );
    } else {
      _previewAssetId = targetNode.assetId;
    }

    final previewState = _previewBackend.state;
    final localPositionSeconds = targetNode.sourcePositionSeconds;
    final shouldForce = didAttachSource ||
        (!_engineController.isPlaying && !_isTimelineScrubbing);
    final shouldSyncTransport = didAttachSource ||
        _engineController.isPlaying != previewState.isPlaying ||
        !_engineController.isPlaying;
    if (shouldSyncTransport) {
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
    _exportController.removeListener(_handleExportChanged);
    unawaited(_engineController.shutdown());
    _previewSeekDebounce?.cancel();
    unawaited(_previewBackend.disposeBackend());
    _engineController.dispose();
    _exportController.dispose();
    _assetLibrary.dispose();
    super.dispose();
  }

  void _handleEngineChanged() {
    final handle = _engineController.projectHandle;
    if (handle != null) {
      unawaited(_previewBackend.bindProject(handle.id));
    }
    if (_shouldRefreshPreviewScene()) {
      unawaited(_syncPreviewFromEngineState());
    }
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  bool _shouldRefreshPreviewScene() {
    if (!_engineController.isPlaying) {
      return true;
    }
    if (_previewBackend.state.isPlaying != _engineController.isPlaying) {
      return true;
    }
    if (_previewBackend.state.selectedClipId !=
        _engineController.selectedClipId) {
      return true;
    }
    return !_cachedSceneCoversSecond(_engineController.currentSeconds);
  }

  bool _cachedSceneCoversSecond(double seconds) {
    if (_compositionNodes.isEmpty) {
      return false;
    }
    for (final node in _compositionNodes) {
      if (seconds < node.clipStartSeconds ||
          seconds > node.clipEndSeconds + 0.0001) {
        return false;
      }
    }
    for (final node in _audioNodes) {
      if (seconds < node.clipStartSeconds ||
          seconds > node.clipEndSeconds + 0.0001) {
        return false;
      }
    }
    return true;
  }

  void _handleExportChanged() {
    if (!mounted) {
      return;
    }

    final status = _exportController.status;
    if (status.kind == FusionExportStatusKind.completed &&
        status.outputPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to ${status.outputPath}')),
      );
      _exportController.reset();
      return;
    }

    if (status.kind == FusionExportStatusKind.failed &&
        status.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: ${status.errorMessage}')),
      );
      _exportController.reset();
      return;
    }

    setState(() {});
  }

  Future<void> _handleExportPressed() async {
    final projectId = _engineController.projectHandle?.id;
    final source = _previewBackend.state.source;
    if (projectId == null || source == null) {
      return;
    }
    if (source.kind != PreviewSourceKind.video) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Export foundation currently supports video clips only.')),
      );
      return;
    }

    final matchingAudioNode =
        _audioNodes.where((node) => node.clipId == source.id);
    final audioNode =
        matchingAudioNode.isNotEmpty ? matchingAudioNode.first : null;
    final exportSceneNodes = EditorSceneMapper.exportSceneNodes(
      _compositionNodes,
    );
    final exportAudioNodes = EditorSceneMapper.exportAudioNodes(_audioNodes);

    await _exportController.startExport(
      FusionExportRequest(
        projectId: projectId,
        clipId: source.id,
        sourcePath: source.localPath,
        sourceKind: FusionExportSourceKind.video,
        sourceStartSeconds: source.sourceStartSeconds,
        sourceEndSeconds: source.sourceEndSeconds,
        projectWidth: _engineController.projectWidth,
        projectHeight: _engineController.projectHeight,
        clipStartSeconds: source.clipStartSeconds,
        clipEndSeconds: source.clipEndSeconds,
        audioGain: audioNode?.gain ?? 1.0,
        isMuted: audioNode?.isMuted ?? false,
        sceneNodes: exportSceneNodes,
        audioNodes: exportAudioNodes,
        outputFileName:
            'fusion_export_${DateTime.now().millisecondsSinceEpoch}.mp4',
      ),
    );
  }

  void _setCurrentSeconds(double value) {
    unawaited(_engineController.seekSeconds(value));
    final previewState = _previewBackend.state;
    if (previewState.isReady && !previewState.isPlaying) {
      unawaited(() async {
        final node = await _currentPreviewNode(projectSeconds: value);
        if (node == null) {
          return;
        }
        _schedulePreviewSeek(
          node.sourcePositionSeconds,
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
    unawaited(
      _previewBackend
          .syncTransport(
        positionSeconds: pending,
        isPlaying: false,
        force: true,
      )
          .whenComplete(() {
        _previewSeekInFlight = false;
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
      final node = await _currentPreviewNode();
      final localSeconds =
          node?.sourcePositionSeconds ?? previewState.positionSeconds;
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
    unawaited(() async {
      final nodes = await _engineController.compositionAt(
        _engineController.currentSeconds,
      );
      _compositionNodes = nodes;
      EngineCompositionNodeSnapshot? node;
      for (final candidate in nodes) {
        if (candidate.clipId == clipId) {
          node = candidate;
        }
      }
      final asset = node == null
          ? (() {
              final descriptor = _engineController.assetForClipId(clipId);
              if (descriptor == null) {
                return _findAssetById(clipId);
              }
              return _assetFromDescriptor(descriptor);
            })()
          : _assetFromDescriptor(
              _engineController.assetForId(node.assetId) ??
                  EngineAssetDescriptor(
                    id: node.assetId,
                    uri: node.assetUri,
                    kind: node.trackKind,
                    label: node.displayLabel,
                  ),
            );
      if (asset != null && asset.isVisual) {
        await _activatePreviewForAsset(
          asset,
          previewSource: node == null ? null : _previewSourceForNode(node),
        );
      }
      if (mounted) {
        setState(() {});
      }
    }());
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

    setState(() {});
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
        final metadata = await EditorMediaSupport.readVideoMetadataWithRetry(
          asset.localPath!,
        );
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

    if (asset.tab == EditorMediaTab.audio && asset.durationSeconds == null) {
      try {
        final metadata =
            await EditorMediaSupport.readAudioMetadata(asset.localPath!);
        final updatedAsset = asset.copyWith(
          durationSeconds: metadata.durationSeconds,
        );
        _replaceAsset(updatedAsset);
        return updatedAsset;
      } catch (error, stackTrace) {
        debugPrint('Fusion Video: audio metadata probe failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        return asset;
      }
    }

    if (asset.tab == EditorMediaTab.image &&
        (asset.width == null || asset.height == null)) {
      try {
        final metadata = await EditorMediaSupport.readImageMetadata(
          asset.localPath!,
        );
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
      clipStartSeconds: 0,
      clipEndSeconds: asset.durationSeconds,
      durationSeconds: asset.durationSeconds,
      width: asset.width,
      height: asset.height,
      sourceStartSeconds: 0,
      sourceEndSeconds: asset.durationSeconds,
      clipDurationSeconds: asset.durationSeconds,
    );
  }

  PreviewSource _previewSourceForNode(EngineCompositionNodeSnapshot node) {
    final descriptor = _engineController.assetForId(node.assetId);
    return EditorSceneMapper.previewSourceForNode(
      node,
      descriptor: descriptor,
    );
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
        final label = tab == EditorMediaTab.text ? 'New Text' : 'Lip Sync';
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
        durationSeconds: importedFile.durationSeconds,
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
            kind: EditorMediaSupport.engineTrackKindFor(newAsset.tab),
            label: newAsset.label,
            durationSeconds: newAsset.durationSeconds,
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

  Future<EditorImportedAssetFile?> _pickAssetForTab(EditorMediaTab tab) async {
    switch (tab) {
      case EditorMediaTab.video:
        final file = await _imagePicker.pickVideo(
          source: ImageSource.gallery,
        );
        if (file == null) {
          return null;
        }
        final metadata =
            await EditorMediaSupport.readVideoMetadataWithRetry(file.path);
        return EditorImportedAssetFile(
          path: file.path,
          name: file.name,
          durationSeconds: metadata.durationSeconds,
          width: metadata.width,
          height: metadata.height,
        );
      case EditorMediaTab.image:
        final file = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          requestFullMetadata: false,
        );
        if (file == null) {
          return null;
        }
        final metadata = await EditorMediaSupport.readImageMetadata(file.path);
        return EditorImportedAssetFile(
          path: file.path,
          name: file.name,
          width: metadata.width,
          height: metadata.height,
        );
      case EditorMediaTab.audio:
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: false,
          type: FileType.custom,
          allowedExtensions: EditorMediaSupport.allowedExtensionsFor(tab),
        );
        if (result == null || result.files.isEmpty) {
          return null;
        }
        final file = result.files.single;
        if (file.path == null) {
          return null;
        }
        final metadata = await EditorMediaSupport.readAudioMetadata(file.path!);
        return EditorImportedAssetFile(
          path: file.path!,
          name: file.name,
          durationSeconds: metadata.durationSeconds,
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
      if (preparedAsset.tab == EditorMediaTab.video &&
          ((preparedAsset.durationSeconds ?? 0) <= 0 ||
              preparedAsset.width == null ||
              preparedAsset.height == null)) {
        throw StateError(
          'Unable to read complete video metadata before adding it to the timeline.',
        );
      }
      await _engineController.importAsset(
        EngineAssetDescriptor(
          id: preparedAsset.id,
          uri: preparedAsset.localPath ?? '',
          kind: EditorMediaSupport.engineTrackKindFor(preparedAsset.tab),
          label: preparedAsset.label,
          durationSeconds: preparedAsset.durationSeconds,
          width: preparedAsset.width,
          height: preparedAsset.height,
        ),
      );
      final durationSeconds = preparedAsset.durationSeconds ??
          EditorMediaSupport.defaultDurationFor(preparedAsset.tab);
      final trackKind = EditorMediaSupport.engineTrackKindFor(
        preparedAsset.tab,
      );
      if (preparedAsset.tab == EditorMediaTab.audio && durationSeconds <= 0) {
        throw StateError(
          'Unable to read audio duration before adding it to the timeline.',
        );
      }
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

  @override
  Widget build(BuildContext context) {
    final currentSeconds = _effectiveCurrentSeconds;
    final isPlaying = _effectiveIsPlaying;
    final tracks = _engineController.tracks;
    final selectedClipId = _engineController.selectedClipId;
    final diagnostics = EditorRuntimeDiagnostics.capture(
      engineStatus: _engineController.status,
      engineDurationSeconds: _engineController.durationSeconds,
      previewState: _previewBackend.state,
      compositionNodes: _compositionNodes,
      audioNodes: _audioNodes,
      selectedClipId: selectedClipId,
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              color: FxPalette.background,
              child: Column(
                children: [
                  EditorTopBar(
                    onShare: _handleExportPressed,
                    isExporting: _exportController.isExporting,
                    exportProgress: _exportController.status.progress,
                  ),
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
                  if (kDebugMode)
                    EditorDiagnosticsPanel(diagnostics: diagnostics),
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
