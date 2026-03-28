import 'export_backend.dart';
import 'export_session_bridge.dart';

class NativeExportBackend implements FusionExportBackend {
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('Native export backend is not initialized.');
    }
  }

  @override
  Future<FusionExportStatus> startExport(FusionExportRequest request) async {
    _ensureInitialized();
    return FusionExportSessionBridge.startExport(request);
  }

  @override
  Future<FusionExportStatus> pollStatus(String jobId) async {
    _ensureInitialized();
    return FusionExportSessionBridge.pollStatus(jobId);
  }

  @override
  Future<void> cancelExport(String jobId) async {
    _ensureInitialized();
    await FusionExportSessionBridge.cancelExport(jobId);
  }
}
