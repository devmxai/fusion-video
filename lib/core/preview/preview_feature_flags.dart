import 'package:flutter/foundation.dart';

class PreviewFeatureFlags {
  const PreviewFeatureFlags._();

  static const bool useEngineDrivenPreview = bool.fromEnvironment(
    'FUSION_USE_ENGINE_DRIVEN_PREVIEW',
    defaultValue: true,
  );

  static const bool _legacyAndroidPreviewSurfaceOverride = bool.fromEnvironment(
    'FUSION_USE_LEGACY_ANDROID_PREVIEW_SURFACE',
    defaultValue: false,
  );

  static bool get useLegacyAndroidPreviewSurface =>
      !kReleaseMode && _legacyAndroidPreviewSurfaceOverride;

  static bool get useAndroidEngineSurface => !useLegacyAndroidPreviewSurface;
}
