import 'engine_bridge_ffi.dart';
import 'engine_bridge_stub.dart';
import 'engine_contract.dart';

FusionVideoEngineBridge createFusionVideoEngineBridge() {
  return FusionVideoFfiBridge.tryCreate() ?? FusionVideoEngineStub();
}
