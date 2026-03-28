import 'package:flutter_test/flutter_test.dart';

import 'package:fusion_video/core/export/export_backend.dart';
import 'package:fusion_video/core/export/export_session_controller.dart';

class _FakeExportBackend implements FusionExportBackend {
  bool initialized = false;
  FusionExportStatus _currentStatus = const FusionExportStatus.idle();

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<FusionExportStatus> startExport(FusionExportRequest request) async {
    _currentStatus = const FusionExportStatus(
      kind: FusionExportStatusKind.exporting,
      jobId: 'job-1',
      progress: 0.1,
    );
    return _currentStatus;
  }

  @override
  Future<FusionExportStatus> pollStatus(String jobId) async {
    _currentStatus = const FusionExportStatus(
      kind: FusionExportStatusKind.completed,
      jobId: 'job-1',
      progress: 1,
      outputPath: '/tmp/fusion_export.mp4',
    );
    return _currentStatus;
  }

  @override
  Future<void> cancelExport(String jobId) async {
    _currentStatus = const FusionExportStatus(
      kind: FusionExportStatusKind.cancelled,
      jobId: 'job-1',
      progress: 0,
    );
  }
}

void main() {
  test('export controller starts and completes export job', () async {
    final backend = _FakeExportBackend();
    final controller = FusionExportSessionController(backend: backend);

    await controller.startExport(
      const FusionExportRequest(
        projectId: 1,
        clipId: 'clip-1',
        sourcePath: '/tmp/clip-1.mp4',
        sourceKind: FusionExportSourceKind.video,
        sourceStartSeconds: 0,
        sourceEndSeconds: 2,
      ),
    );

    expect(backend.initialized, isTrue);
    expect(controller.status.kind, FusionExportStatusKind.exporting);
    expect(controller.status.jobId, 'job-1');

    await Future<void>.delayed(const Duration(milliseconds: 260));

    expect(controller.status.kind, FusionExportStatusKind.completed);
    expect(controller.status.outputPath, '/tmp/fusion_export.mp4');

    controller.dispose();
  });
}
