import 'dart:async';

import 'package:flutter/foundation.dart';

import 'export_backend.dart';

class FusionExportSessionController extends ChangeNotifier {
  FusionExportSessionController({
    required FusionExportBackend backend,
  }) : _backend = backend;

  final FusionExportBackend _backend;

  FusionExportStatus _status = const FusionExportStatus.idle();
  Timer? _pollTimer;
  bool _initialized = false;

  FusionExportStatus get status => _status;
  bool get isExporting => _status.kind == FusionExportStatusKind.exporting;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _backend.initialize();
    _initialized = true;
  }

  Future<void> startExport(FusionExportRequest request) async {
    await initialize();
    _pollTimer?.cancel();
    _status = const FusionExportStatus(
      kind: FusionExportStatusKind.exporting,
      progress: 0,
    );
    notifyListeners();

    try {
      final started = await _backend.startExport(request);
      _status = started;
      notifyListeners();
      if (_status.jobId != null && !_status.isTerminal) {
        _beginPolling(_status.jobId!);
      }
    } catch (error) {
      _status = FusionExportStatus(
        kind: FusionExportStatusKind.failed,
        errorMessage: error.toString(),
      );
      notifyListeners();
    }
  }

  Future<void> cancelExport() async {
    final jobId = _status.jobId;
    if (jobId == null) {
      return;
    }
    await _backend.cancelExport(jobId);
    _pollTimer?.cancel();
    _status = _status.copyWith(
      kind: FusionExportStatusKind.cancelled,
      progress: 0,
    );
    notifyListeners();
  }

  void reset() {
    _pollTimer?.cancel();
    _status = const FusionExportStatus.idle();
    notifyListeners();
  }

  void _beginPolling(String jobId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 220), (_) async {
      final status = await _backend.pollStatus(jobId);
      _status = status;
      notifyListeners();
      if (status.isTerminal) {
        _pollTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
