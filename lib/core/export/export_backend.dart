enum FusionExportSourceKind {
  video,
  image,
}

enum FusionExportStatusKind {
  idle,
  exporting,
  completed,
  failed,
  cancelled,
}

class FusionExportSceneNode {
  const FusionExportSceneNode({
    required this.clipId,
    required this.assetId,
    required this.kind,
    required this.localPath,
    this.displayLabel,
    required this.clipStartSeconds,
    required this.clipEndSeconds,
    required this.sourceStartSeconds,
    required this.sourceEndSeconds,
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
  final double sourceStartSeconds;
  final double sourceEndSeconds;
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

class FusionExportAudioNode {
  const FusionExportAudioNode({
    required this.clipId,
    required this.assetId,
    required this.kind,
    required this.localPath,
    this.displayLabel,
    required this.clipStartSeconds,
    required this.clipEndSeconds,
    required this.sourceStartSeconds,
    required this.sourceEndSeconds,
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
  final double sourceStartSeconds;
  final double sourceEndSeconds;
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
      'sourceStartSeconds': sourceStartSeconds,
      'sourceEndSeconds': sourceEndSeconds,
      'gain': gain,
      'isMuted': isMuted,
    };
  }
}

class FusionExportRequest {
  const FusionExportRequest({
    required this.projectId,
    required this.clipId,
    required this.sourcePath,
    required this.sourceKind,
    required this.sourceStartSeconds,
    this.sourceEndSeconds,
    this.projectWidth,
    this.projectHeight,
    this.clipStartSeconds = 0,
    this.clipEndSeconds,
    this.audioGain = 1.0,
    this.isMuted = false,
    this.sceneNodes = const <FusionExportSceneNode>[],
    this.audioNodes = const <FusionExportAudioNode>[],
    this.outputFileName,
  });

  final int projectId;
  final String clipId;
  final String sourcePath;
  final FusionExportSourceKind sourceKind;
  final double sourceStartSeconds;
  final double? sourceEndSeconds;
  final int? projectWidth;
  final int? projectHeight;
  final double clipStartSeconds;
  final double? clipEndSeconds;
  final double audioGain;
  final bool isMuted;
  final List<FusionExportSceneNode> sceneNodes;
  final List<FusionExportAudioNode> audioNodes;
  final String? outputFileName;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'projectId': projectId,
      'clipId': clipId,
      'sourcePath': sourcePath,
      'sourceKind': switch (sourceKind) {
        FusionExportSourceKind.video => 'video',
        FusionExportSourceKind.image => 'image',
      },
      'sourceStartSeconds': sourceStartSeconds,
      'sourceEndSeconds': sourceEndSeconds,
      'projectWidth': projectWidth,
      'projectHeight': projectHeight,
      'clipStartSeconds': clipStartSeconds,
      'clipEndSeconds': clipEndSeconds,
      'audioGain': audioGain,
      'isMuted': isMuted,
      'sceneNodes': sceneNodes.map((node) => node.toMap()).toList(),
      'audioNodes': audioNodes.map((node) => node.toMap()).toList(),
      'outputFileName': outputFileName,
    };
  }
}

class FusionExportStatus {
  const FusionExportStatus({
    required this.kind,
    this.jobId,
    this.progress = 0,
    this.outputPath,
    this.errorMessage,
  });

  const FusionExportStatus.idle() : this(kind: FusionExportStatusKind.idle);

  final FusionExportStatusKind kind;
  final String? jobId;
  final double progress;
  final String? outputPath;
  final String? errorMessage;

  bool get isTerminal =>
      kind == FusionExportStatusKind.completed ||
      kind == FusionExportStatusKind.failed ||
      kind == FusionExportStatusKind.cancelled;

  FusionExportStatus copyWith({
    FusionExportStatusKind? kind,
    String? jobId,
    double? progress,
    String? outputPath,
    bool clearOutputPath = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return FusionExportStatus(
      kind: kind ?? this.kind,
      jobId: jobId ?? this.jobId,
      progress: progress ?? this.progress,
      outputPath: clearOutputPath ? null : (outputPath ?? this.outputPath),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

abstract class FusionExportBackend {
  Future<void> initialize();

  Future<FusionExportStatus> startExport(FusionExportRequest request);

  Future<FusionExportStatus> pollStatus(String jobId);

  Future<void> cancelExport(String jobId);
}
