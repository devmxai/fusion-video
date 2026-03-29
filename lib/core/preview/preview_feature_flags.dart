class PreviewFeatureFlags {
  const PreviewFeatureFlags._();

  static const bool useEngineDrivenPreview = bool.fromEnvironment(
    'FUSION_USE_ENGINE_DRIVEN_PREVIEW',
    defaultValue: false,
  );
}
