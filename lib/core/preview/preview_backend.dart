import 'package:flutter/material.dart';

enum PreviewSourceKind {
  video,
  image,
}

class PreviewCompositionNode {
  const PreviewCompositionNode({
    required this.clipId,
    required this.assetId,
    required this.kind,
    required this.localPath,
    this.displayLabel,
    required this.clipStartSeconds,
    required this.clipEndSeconds,
    required this.sourcePositionSeconds,
    required this.sourceStartSeconds,
    this.sourceEndSeconds,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.opacity,
    required this.rotationDegrees,
    required this.zIndex,
  });

  final String clipId;
  final String assetId;
  final String kind;
  final String localPath;
  final String? displayLabel;
  final double clipStartSeconds;
  final double clipEndSeconds;
  final double sourcePositionSeconds;
  final double sourceStartSeconds;
  final double? sourceEndSeconds;
  final double x;
  final double y;
  final double width;
  final double height;
  final double opacity;
  final double rotationDegrees;
  final int zIndex;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'clipId': clipId,
      'assetId': assetId,
      'kind': kind,
      'localPath': localPath,
      'displayLabel': displayLabel,
      'clipStartSeconds': clipStartSeconds,
      'clipEndSeconds': clipEndSeconds,
      'sourcePositionSeconds': sourcePositionSeconds,
      'sourceStartSeconds': sourceStartSeconds,
      'sourceEndSeconds': sourceEndSeconds,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'opacity': opacity,
      'rotationDegrees': rotationDegrees,
      'zIndex': zIndex,
    };
  }
}

class PreviewAudioNode {
  const PreviewAudioNode({
    required this.clipId,
    required this.assetId,
    required this.kind,
    required this.localPath,
    this.displayLabel,
    required this.clipStartSeconds,
    required this.clipEndSeconds,
    required this.sourcePositionSeconds,
    required this.sourceStartSeconds,
    this.sourceEndSeconds,
    required this.gain,
    required this.isMuted,
  });

  final String clipId;
  final String assetId;
  final String kind;
  final String localPath;
  final String? displayLabel;
  final double clipStartSeconds;
  final double clipEndSeconds;
  final double sourcePositionSeconds;
  final double sourceStartSeconds;
  final double? sourceEndSeconds;
  final double gain;
  final bool isMuted;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'clipId': clipId,
      'assetId': assetId,
      'kind': kind,
      'localPath': localPath,
      'displayLabel': displayLabel,
      'clipStartSeconds': clipStartSeconds,
      'clipEndSeconds': clipEndSeconds,
      'sourcePositionSeconds': sourcePositionSeconds,
      'sourceStartSeconds': sourceStartSeconds,
      'sourceEndSeconds': sourceEndSeconds,
      'gain': gain,
      'isMuted': isMuted,
    };
  }
}

class PreviewSource {
  const PreviewSource({
    required this.id,
    required this.assetId,
    required this.kind,
    required this.localPath,
    this.attachmentId,
    this.clipStartSeconds = 0,
    this.clipEndSeconds,
    this.durationSeconds,
    this.width,
    this.height,
    this.sourceStartSeconds = 0,
    this.sourceEndSeconds,
    this.clipDurationSeconds,
  });

  final String id;
  final String assetId;
  final PreviewSourceKind kind;
  final String localPath;
  final String? attachmentId;
  final double clipStartSeconds;
  final double? clipEndSeconds;
  final double? durationSeconds;
  final int? width;
  final int? height;
  final double sourceStartSeconds;
  final double? sourceEndSeconds;
  final double? clipDurationSeconds;

  String get effectiveAttachmentId => attachmentId ?? id;

  double? get effectiveDurationSeconds =>
      clipDurationSeconds ?? sourceEndSeconds ?? durationSeconds;

  double? get aspectRatio {
    if (width == null || height == null || width == 0 || height == 0) {
      return null;
    }
    return width! / height!;
  }
}

class PreviewBackendState {
  const PreviewBackendState({
    this.source,
    this.upcomingSource,
    this.compositionNodes = const <PreviewCompositionNode>[],
    this.audioNodes = const <PreviewAudioNode>[],
    this.projectWidth,
    this.projectHeight,
    this.baseClipId,
    this.baseClipIds = const <String>[],
    this.selectedClipId,
    this.baseAudioGain = 1,
    this.baseAudioMuted = false,
    this.isReady = false,
    this.isPlaying = false,
    this.transportRevision = 0,
    this.positionSeconds = 0,
    this.durationSeconds = 0,
    this.contentSize,
  });

  final PreviewSource? source;
  final PreviewSource? upcomingSource;
  final List<PreviewCompositionNode> compositionNodes;
  final List<PreviewAudioNode> audioNodes;
  final int? projectWidth;
  final int? projectHeight;
  final String? baseClipId;
  final List<String> baseClipIds;
  final String? selectedClipId;
  final double baseAudioGain;
  final bool baseAudioMuted;
  final bool isReady;
  final bool isPlaying;
  final int transportRevision;
  final double positionSeconds;
  final double durationSeconds;
  final Size? contentSize;

  double? get aspectRatio {
    final size = contentSize;
    if (size != null && size.height > 0) {
      return size.width / size.height;
    }
    return source?.aspectRatio;
  }

  PreviewBackendState copyWith({
    PreviewSource? source,
    bool clearSource = false,
    PreviewSource? upcomingSource,
    bool clearUpcomingSource = false,
    List<PreviewCompositionNode>? compositionNodes,
    List<PreviewAudioNode>? audioNodes,
    int? projectWidth,
    int? projectHeight,
    String? baseClipId,
    bool clearBaseClipId = false,
    List<String>? baseClipIds,
    String? selectedClipId,
    bool clearSelectedClipId = false,
    double? baseAudioGain,
    bool? baseAudioMuted,
    bool? isReady,
    bool? isPlaying,
    int? transportRevision,
    double? positionSeconds,
    double? durationSeconds,
    Size? contentSize,
    bool clearContentSize = false,
  }) {
    return PreviewBackendState(
      source: clearSource ? null : (source ?? this.source),
      upcomingSource:
          clearUpcomingSource ? null : (upcomingSource ?? this.upcomingSource),
      compositionNodes: compositionNodes ?? this.compositionNodes,
      audioNodes: audioNodes ?? this.audioNodes,
      projectWidth: projectWidth ?? this.projectWidth,
      projectHeight: projectHeight ?? this.projectHeight,
      baseClipId: clearBaseClipId ? null : (baseClipId ?? this.baseClipId),
      baseClipIds: clearBaseClipId
          ? const <String>[]
          : (baseClipIds ?? this.baseClipIds),
      selectedClipId:
          clearSelectedClipId ? null : (selectedClipId ?? this.selectedClipId),
      baseAudioGain: baseAudioGain ?? this.baseAudioGain,
      baseAudioMuted: baseAudioMuted ?? this.baseAudioMuted,
      isReady: isReady ?? this.isReady,
      isPlaying: isPlaying ?? this.isPlaying,
      transportRevision: transportRevision ?? this.transportRevision,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      contentSize: clearContentSize ? null : (contentSize ?? this.contentSize),
    );
  }
}

abstract class FusionPreviewBackend extends ChangeNotifier {
  PreviewBackendState get state;

  Future<void> bindProject(int projectId);

  Future<void> syncTransport({
    required double positionSeconds,
    required bool isPlaying,
    bool force = false,
  });

  Future<void> attachSource(
    PreviewSource? source, {
    bool autoplay = false,
    PreviewSource? upcomingSource,
  });

  Future<void> updateSource(
    PreviewSource? source, {
    PreviewSource? upcomingSource,
  });

  Future<void> updateCompositionScene({
    required int projectWidth,
    required int projectHeight,
    required List<PreviewCompositionNode> nodes,
    required List<PreviewAudioNode> audioNodes,
    String? baseClipId,
    List<String>? baseClipIds,
    String? selectedClipId,
    double baseAudioGain = 1,
    bool baseAudioMuted = false,
  });

  Future<void> play();

  Future<void> pause();

  Future<void> seek(double seconds);

  Widget buildView({BoxFit fit = BoxFit.cover});

  Future<void> disposeBackend();
}
