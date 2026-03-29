import 'engine_driven_preview_backend.dart';
import 'native_preview_backend.dart';
import 'preview_backend.dart';
import 'preview_feature_flags.dart';

FusionPreviewBackend createFusionPreviewBackend({
  required int projectId,
}) {
  if (PreviewFeatureFlags.useEngineDrivenPreview) {
    return EngineDrivenPreviewBackend(projectId: projectId);
  }
  return NativePreviewBackend(projectId: projectId);
}
