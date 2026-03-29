import '../../../core/engine/engine_contract.dart';
import '../../../core/media/local_media_probe.dart';
import '../presentation/models/editor_media_tab.dart';

class EditorImportedAssetFile {
  const EditorImportedAssetFile({
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

class EditorImportedAssetMetadata {
  const EditorImportedAssetMetadata({
    this.durationSeconds,
    this.width,
    this.height,
  });

  final double? durationSeconds;
  final int? width;
  final int? height;
}

class EditorMediaSupport {
  const EditorMediaSupport._();

  static EngineTrackKind engineTrackKindFor(EditorMediaTab tab) {
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

  static double defaultDurationFor(EditorMediaTab tab) {
    switch (tab) {
      case EditorMediaTab.video:
      case EditorMediaTab.audio:
        return 0;
      case EditorMediaTab.image:
      case EditorMediaTab.text:
      case EditorMediaTab.lipSync:
        return 3;
    }
  }

  static List<String> allowedExtensionsFor(EditorMediaTab tab) {
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

  static Future<EditorImportedAssetMetadata> readVideoMetadata(
    String path,
  ) async {
    final metadata = await probeVideoMetadata(path);
    return EditorImportedAssetMetadata(
      durationSeconds: metadata.durationSeconds,
      width: metadata.width,
      height: metadata.height,
    );
  }

  static Future<EditorImportedAssetMetadata> readVideoMetadataWithRetry(
    String path,
  ) async {
    var last = const EditorImportedAssetMetadata();
    for (var attempt = 0; attempt < 4; attempt++) {
      last = await readVideoMetadata(path);
      if ((last.durationSeconds ?? 0) > 0 &&
          (last.width ?? 0) > 0 &&
          (last.height ?? 0) > 0) {
        return last;
      }
      await Future<void>.delayed(Duration(milliseconds: 120 * (attempt + 1)));
    }
    return last;
  }

  static Future<EditorImportedAssetMetadata> readImageMetadata(
    String path,
  ) async {
    final metadata = await probeImageMetadata(path);
    return EditorImportedAssetMetadata(
      width: metadata.width,
      height: metadata.height,
    );
  }

  static Future<EditorImportedAssetMetadata> readAudioMetadata(
    String path,
  ) async {
    final metadata = await probeAudioMetadata(path);
    return EditorImportedAssetMetadata(
      durationSeconds: metadata.durationSeconds,
    );
  }
}
