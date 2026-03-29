import 'dart:io';
import 'dart:ui' as ui;

import 'native_media_probe.dart';

class LocalMediaMetadata {
  const LocalMediaMetadata({
    this.durationSeconds,
    this.width,
    this.height,
  });

  final double? durationSeconds;
  final int? width;
  final int? height;
}

Future<LocalMediaMetadata> probeVideoMetadata(String path) async {
  final nativeResult = await NativeMediaProbe.probe(path: path, kind: 'video');
  if (nativeResult != null) {
    return LocalMediaMetadata(
      durationSeconds: (nativeResult['durationSeconds'] as num?)?.toDouble(),
      width: (nativeResult['width'] as num?)?.toInt(),
      height: (nativeResult['height'] as num?)?.toInt(),
    );
  }

  return const LocalMediaMetadata();
}

Future<LocalMediaMetadata> probeAudioMetadata(String path) async {
  final nativeResult = await NativeMediaProbe.probe(path: path, kind: 'audio');
  if (nativeResult != null) {
    return LocalMediaMetadata(
      durationSeconds: (nativeResult['durationSeconds'] as num?)?.toDouble(),
    );
  }

  return const LocalMediaMetadata();
}

Future<LocalMediaMetadata> probeImageMetadata(String path) async {
  final nativeResult = await NativeMediaProbe.probe(path: path, kind: 'image');
  if (nativeResult != null) {
    return LocalMediaMetadata(
      width: (nativeResult['width'] as num?)?.toInt(),
      height: (nativeResult['height'] as num?)?.toInt(),
    );
  }

  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final metadata = LocalMediaMetadata(
    width: frame.image.width,
    height: frame.image.height,
  );
  frame.image.dispose();
  codec.dispose();
  return metadata;
}
