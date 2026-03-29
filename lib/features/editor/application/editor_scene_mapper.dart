import '../../../core/engine/engine_contract.dart';
import '../../../core/export/export_backend.dart';
import '../../../core/preview/preview_backend.dart';

typedef AssetLabelResolver = String? Function(String assetId);

class EditorSceneMapper {
  const EditorSceneMapper._();

  static EngineCompositionNodeSnapshot? resolveBasePreviewNode(
    List<EngineCompositionNodeSnapshot> nodes, {
    required bool isPlaying,
    String? selectedClipId,
  }) {
    if (nodes.isEmpty) {
      return null;
    }

    if (selectedClipId != null && !isPlaying) {
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

  static PreviewSource previewSourceForNode(
    EngineCompositionNodeSnapshot node, {
    EngineAssetDescriptor? descriptor,
  }) {
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

  static List<PreviewCompositionNode> previewCompositionNodes(
    List<EngineCompositionNodeSnapshot> nodes, {
    AssetLabelResolver? assetLabelResolver,
  }) {
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
          kind: _kindName(node.trackKind),
          localPath: node.assetUri,
          displayLabel: node.displayLabel ??
              assetLabelResolver?.call(node.assetId) ??
              _defaultLabel(node.trackKind),
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

  static List<PreviewAudioNode> previewAudioNodes(
    List<EngineAudioNodeSnapshot> nodes,
  ) {
    return nodes
        .where((node) => node.trackKind == EngineTrackKind.audio)
        .map(
          (node) => PreviewAudioNode(
            clipId: node.clipId,
            assetId: node.assetId,
            kind: _kindName(node.trackKind),
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

  static List<FusionExportSceneNode> exportSceneNodes(
    List<EngineCompositionNodeSnapshot> nodes,
  ) {
    return nodes
        .map(
          (node) => FusionExportSceneNode(
            clipId: node.clipId,
            assetId: node.assetId,
            kind: _kindName(node.trackKind),
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

  static List<FusionExportAudioNode> exportAudioNodes(
    List<EngineAudioNodeSnapshot> nodes,
  ) {
    return nodes
        .map(
          (node) => FusionExportAudioNode(
            clipId: node.clipId,
            assetId: node.assetId,
            kind: _kindName(node.trackKind),
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

  static bool shouldAttachPreviewSource(
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

  static String _kindName(EngineTrackKind kind) {
    switch (kind) {
      case EngineTrackKind.video:
        return 'video';
      case EngineTrackKind.image:
        return 'image';
      case EngineTrackKind.audio:
        return 'audio';
      case EngineTrackKind.text:
        return 'text';
      case EngineTrackKind.lipSync:
        return 'lipSync';
      case EngineTrackKind.effect:
        return 'effect';
    }
  }

  static String _defaultLabel(EngineTrackKind kind) {
    switch (kind) {
      case EngineTrackKind.video:
        return 'Video';
      case EngineTrackKind.image:
        return 'Image';
      case EngineTrackKind.audio:
        return 'Audio';
      case EngineTrackKind.text:
        return 'Text';
      case EngineTrackKind.lipSync:
        return 'Lip Sync';
      case EngineTrackKind.effect:
        return 'Effect';
    }
  }
}
