import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/engine/engine_contract.dart';
import '../../../../core/engine/engine_session_controller.dart';
import '../../../../core/export/export_backend.dart';
import '../../../../core/export/export_session_controller.dart';
import '../../../../core/export/native_export_backend.dart';
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
        durationSeconds: _timelineDuration,
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

  EngineCompositionNodeSnapshot? _resolveBasePreviewNode(
    List<EngineCompositionNodeSnapshot> nodes, {
    String? selectedClipId,
  }) {
    if (nodes.isEmpty) {
      return null;
    }

    if (selectedClipId != null && !_engineController.isPlaying) {
      for (final node in nodes.reversed) {
        if (node.clipId == selectedClipId &&
            (node.trackKind == EngineTrackKind.video ||
                node.trackKind == EngineTrackKind.image)) {
          return node;
        }
      }
    }

    for (final node in nodes) {
      if (node.trackKind == EngineTrackKind.video ||
          node.trackKind == EngineTrackKind.image) {
        return node;
      }
    }
    return null;
  }

  Future<EngineCompositionNodeSnapshot?> _currentPreviewNode({
    double? projectSeconds,
  }) async {
    final seconds = projectSeconds ?? _engineController.currentSeconds;
    final nodes = await _engineController.compositionAt(seconds);
    _compositionNodes = nodes;
    return _resolveBasePreviewNode(
      nodes,
      selectedClipId: _engineController.selectedClipId,
    );
  }

  Future<void> _syncPreviewFromEngineState() async {
    final targetNode = await _currentPreviewNode();
    _audioNodes = await _engineController.audioNodesAt(
      _engineController.currentSeconds,
    );
    await _previewBackend.updateCompositionScene(
      projectWidth: _engineController.projectWidth,
      projectHeight: _engineController.projectHeight,
      nodes: _previewCompositionNodesFromScene(_compositionNodes),
      audioNodes: _previewAudioNodesFromScene(_audioNodes),
      baseClipId: targetNode?.clipId,
      selectedClipId: _engineController.selectedClipId,
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
    final didAttachSource =
        _shouldAttachPreviewSource(currentSource, targetSource);
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
    final exportSceneNodes =
        _exportSceneNodesFromCompositionNodes(_compositionNodes);
    final exportAudioNodes = _exportAudioNodesFromAudioNodes(_audioNodes);

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
        final metadata = await _readVideoMetadataWithRetry(asset.localPath!);
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
    return PreviewSource(
      id: node.clipId,
      assetId: node.assetId,
      kind: node.trackKind == EngineTrackKind.video
          ? PreviewSourceKind.video
          : PreviewSourceKind.image,
      localPath: node.assetUri,
      clipStartSeconds: node.clipStartSeconds,
      clipEndSeconds: node.clipEndSeconds,
      durationSeconds: descriptor?.durationSeconds,
      width: descriptor?.width,
      height: descriptor?.height,
      sourceStartSeconds: node.sourceStartSeconds,
      sourceEndSeconds: node.sourceEndSeconds,
      clipDurationSeconds: node.clipDurationSeconds,
    );
  }

  List<PreviewCompositionNode> _previewCompositionNodesFromScene(
    List<EngineCompositionNodeSnapshot> nodes,
  ) {
    final previewNodes = <PreviewCompositionNode>[];
    for (final node in nodes) {
      if (node.trackKind == EngineTrackKind.audio ||
          node.trackKind == EngineTrackKind.effect) {
        continue;
      }
      previewNodes.add(
        PreviewCompositionNode(
          clipId: node.clipId,
          assetId: node.assetId,
          kind: switch (node.trackKind) {
            EngineTrackKind.video => 'video',
            EngineTrackKind.image => 'image',
            EngineTrackKind.text => 'text',
            EngineTrackKind.lipSync => 'lipSync',
            EngineTrackKind.audio => 'audio',
            EngineTrackKind.effect => 'effect',
          },
          localPath: node.assetUri,
          displayLabel: node.displayLabel ??
              _findAssetById(node.assetId)?.label ??
              switch (node.trackKind) {
                EngineTrackKind.video => 'Video',
                EngineTrackKind.image => 'Image',
                EngineTrackKind.audio => 'Audio',
                EngineTrackKind.text => 'Text',
                EngineTrackKind.lipSync => 'Lip Sync',
                EngineTrackKind.effect => 'Effect',
              },
          clipStartSeconds: node.clipStartSeconds,
          clipEndSeconds: node.clipEndSeconds,
          sourcePositionSeconds: node.sourcePositionSeconds,
          sourceStartSeconds: node.sourceStartSeconds,
          sourceEndSeconds: node.sourceEndSeconds,
          x: node.transform.x,
          y: node.transform.y,
          width: node.transform.width,
          height: node.transform.height,
          opacity: node.transform.opacity,
          rotationDegrees: node.transform.rotationDegrees,
          zIndex: node.transform.zIndex,
        ),
      );
    }
    previewNodes.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return previewNodes;
  }

  List<PreviewAudioNode> _previewAudioNodesFromScene(
    List<EngineAudioNodeSnapshot> nodes,
  ) {
    return nodes
        .map(
          (node) => PreviewAudioNode(
            clipId: node.clipId,
            assetId: node.assetId,
            kind: switch (node.trackKind) {
              EngineTrackKind.video => 'video',
              EngineTrackKind.audio => 'audio',
              EngineTrackKind.image => 'image',
              EngineTrackKind.text => 'text',
              EngineTrackKind.lipSync => 'lipSync',
              EngineTrackKind.effect => 'effect',
            },
            localPath: node.assetUri,
            displayLabel: node.displayLabel,
            clipStartSeconds: node.clipStartSeconds,
            clipEndSeconds: node.clipEndSeconds,
            sourcePositionSeconds: node.sourcePositionSeconds,
            sourceStartSeconds: node.sourceStartSeconds,
            sourceEndSeconds: node.sourceEndSeconds,
            gain: node.gain,
            isMuted: node.isMuted,
          ),
        )
        .toList(growable: false);
  }

  List<FusionExportSceneNode> _exportSceneNodesFromCompositionNodes(
    List<EngineCompositionNodeSnapshot> nodes,
  ) {
    return nodes
        .map(
          (node) => FusionExportSceneNode(
            clipId: node.clipId,
            assetId: node.assetId,
            kind: switch (node.trackKind) {
              EngineTrackKind.video => 'video',
              EngineTrackKind.image => 'image',
              EngineTrackKind.audio => 'audio',
              EngineTrackKind.text => 'text',
              EngineTrackKind.lipSync => 'lipSync',
              EngineTrackKind.effect => 'effect',
            },
            localPath: node.assetUri,
            displayLabel: node.displayLabel,
            clipStartSeconds: node.clipStartSeconds,
            clipEndSeconds: node.clipEndSeconds,
            sourceStartSeconds: node.sourceStartSeconds,
            sourceEndSeconds: node.sourceEndSeconds,
            x: node.transform.x,
            y: node.transform.y,
            width: node.transform.width,
            height: node.transform.height,
            opacity: node.transform.opacity,
            rotationDegrees: node.transform.rotationDegrees,
            zIndex: node.transform.zIndex,
          ),
        )
        .toList(growable: false);
  }

  List<FusionExportAudioNode> _exportAudioNodesFromAudioNodes(
    List<EngineAudioNodeSnapshot> nodes,
  ) {
    return nodes
        .map(
          (node) => FusionExportAudioNode(
            clipId: node.clipId,
            assetId: node.assetId,
            kind: switch (node.trackKind) {
              EngineTrackKind.video => 'video',
              EngineTrackKind.image => 'image',
              EngineTrackKind.audio => 'audio',
              EngineTrackKind.text => 'text',
              EngineTrackKind.lipSync => 'lipSync',
              EngineTrackKind.effect => 'effect',
            },
            localPath: node.assetUri,
            displayLabel: node.displayLabel,
            clipStartSeconds: node.clipStartSeconds,
            clipEndSeconds: node.clipEndSeconds,
            sourceStartSeconds: node.sourceStartSeconds,
            sourceEndSeconds: node.sourceEndSeconds,
            gain: node.gain,
            isMuted: node.isMuted,
          ),
        )
        .toList(growable: false);
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
            kind: _engineTrackKindFor(newAsset.tab),
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

  Future<_ImportedAssetFile?> _pickAssetForTab(EditorMediaTab tab) async {
    switch (tab) {
      case EditorMediaTab.video:
        final file = await _imagePicker.pickVideo(
          source: ImageSource.gallery,
        );
        if (file == null) {
          return null;
        }
        final metadata = await _readVideoMetadataWithRetry(file.path);
        return _ImportedAssetFile(
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
          kind: _engineTrackKindFor(preparedAsset.tab),
          label: preparedAsset.label,
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

  Future<_ImportedAssetMetadata> _readVideoMetadataWithRetry(
      String path) async {
    var last = const _ImportedAssetMetadata();
    for (var attempt = 0; attempt < 4; attempt++) {
      last = await _readVideoMetadata(path);
      if ((last.durationSeconds ?? 0) > 0 &&
          (last.width ?? 0) > 0 &&
          (last.height ?? 0) > 0) {
        return last;
      }
      await Future<void>.delayed(Duration(milliseconds: 120 * (attempt + 1)));
    }
    return last;
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
    this.durationSeconds,
    this.width,
    this.height,
  });

  final String path;
  final String name;
  final double? durationSeconds;
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
