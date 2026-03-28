import 'package:flutter/material.dart';

enum PreviewSourceKind {
  video,
  image,
}

class PreviewSource {
  const PreviewSource({
    required this.id,
    required this.assetId,
    required this.kind,
    required this.localPath,
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
  final double? durationSeconds;
  final int? width;
  final int? height;
  final double sourceStartSeconds;
  final double? sourceEndSeconds;
  final double? clipDurationSeconds;

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
    this.isReady = false,
    this.isPlaying = false,
    this.positionSeconds = 0,
    this.durationSeconds = 0,
    this.contentSize,
  });

  final PreviewSource? source;
  final bool isReady;
  final bool isPlaying;
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
    bool? isReady,
    bool? isPlaying,
    double? positionSeconds,
    double? durationSeconds,
    Size? contentSize,
    bool clearContentSize = false,
  }) {
    return PreviewBackendState(
      source: clearSource ? null : (source ?? this.source),
      isReady: isReady ?? this.isReady,
      isPlaying: isPlaying ?? this.isPlaying,
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
  });

  Future<void> play();

  Future<void> pause();

  Future<void> seek(double seconds);

  Widget buildView({BoxFit fit = BoxFit.cover});

  Future<void> disposeBackend();
}
