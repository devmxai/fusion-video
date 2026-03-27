import 'dart:async';

import 'engine_contract.dart';

class FusionVideoEngineStub implements FusionVideoEngineBridge {
  final StreamController<EngineStatusSnapshot> _statusController =
      StreamController<EngineStatusSnapshot>.broadcast();

  @override
  Future<void> initialize() async {}

  @override
  Future<EngineProjectHandle> createProject(EngineProjectConfig config) async {
    return const EngineProjectHandle(1);
  }

  @override
  Future<void> disposeProject(EngineProjectHandle handle) async {}

  @override
  Future<void> importAsset(
    EngineProjectHandle handle,
    EngineAssetDescriptor asset,
  ) async {}

  @override
  Future<void> play(EngineProjectHandle handle) async {}

  @override
  Future<void> pause(EngineProjectHandle handle) async {}

  @override
  Future<void> seek(
    EngineProjectHandle handle,
    EngineTimelinePosition position,
  ) async {}

  @override
  Future<void> splitSelectedClip(
    EngineProjectHandle handle,
    EngineTimelinePosition position,
  ) async {}

  @override
  Future<void> trimClipLeft(
    EngineProjectHandle handle,
    String clipId,
    EngineTimelinePosition position,
  ) async {}

  @override
  Future<void> trimClipRight(
    EngineProjectHandle handle,
    String clipId,
    EngineTimelinePosition position,
  ) async {}

  @override
  Future<void> deleteClip(
    EngineProjectHandle handle,
    String clipId,
  ) async {}

  @override
  Future<void> duplicateClip(
    EngineProjectHandle handle,
    String clipId,
  ) async {}

  @override
  Stream<EngineStatusSnapshot> watchStatus(EngineProjectHandle handle) {
    return _statusController.stream;
  }
}
