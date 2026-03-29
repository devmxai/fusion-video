class PreviewFeatureFlags {
  const PreviewFeatureFlags._();

  static const bool useEngineDrivenPreview = bool.fromEnvironment(
    'FUSION_USE_ENGINE_DRIVEN_PREVIEW',
    defaultValue: true,
  );

  static const bool useAndroidEngineSurface = bool.fromEnvironment(
    'FUSION_USE_ANDROID_ENGINE_SURFACE',
    defaultValue: false,
  );
}
