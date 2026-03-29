import 'dart:async';

import 'engine_contract.dart';

class SimulatedProjectRuntime {
  SimulatedProjectRuntime(this.config)
      : _controller = StreamController<EngineStatusSnapshot>.broadcast() {
    _durationSeconds = config.durationSeconds;
    _emit();
  }

  final EngineProjectConfig config;
  final StreamController<EngineStatusSnapshot> _controller;
  Timer? _timer;
  DateTime? _lastTickAt;
  double _seconds = 0;
  late double _durationSeconds;
  EnginePlaybackState _playbackState = EnginePlaybackState.stopped;

  Stream<EngineStatusSnapshot> get stream => _controller.stream;

  void updateDuration(double seconds) {
    final nextDuration = seconds < 0 ? 0.0 : seconds;
    _durationSeconds = nextDuration;
    if (_seconds > _durationSeconds) {
      _seconds = _durationSeconds;
    }
    if (_durationSeconds <= 0 &&
        _playbackState == EnginePlaybackState.playing) {
      pause();
      return;
    }
    _emit();
  }

  void play() {
    if (_playbackState == EnginePlaybackState.playing) {
      return;
    }
    if (_durationSeconds <= 0) {
      _seconds = 0;
      _playbackState = EnginePlaybackState.stopped;
      _emit();
      return;
    }
    _playbackState = EnginePlaybackState.playing;
    _lastTickAt = DateTime.now();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
    _emit();
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    _lastTickAt = null;
    _playbackState = _seconds <= 0
        ? EnginePlaybackState.stopped
        : EnginePlaybackState.paused;
    _emit();
  }

  void seek(double seconds) {
    _seconds = seconds.clamp(0.0, _durationSeconds);
    if (_playbackState == EnginePlaybackState.playing) {
      _lastTickAt = DateTime.now();
    } else {
      _playbackState = _seconds <= 0
          ? EnginePlaybackState.stopped
          : EnginePlaybackState.paused;
    }
    _emit();
  }

  void _tick() {
    if (_playbackState != EnginePlaybackState.playing) {
      return;
    }

    final now = DateTime.now();
    final last = _lastTickAt ?? now;
    _lastTickAt = now;
    final deltaSeconds =
        now.difference(last).inMicroseconds / Duration.microsecondsPerSecond;

    if (deltaSeconds <= 0) {
      return;
    }

    _seconds = (_seconds + deltaSeconds).clamp(0.0, _durationSeconds);
    if (_seconds >= _durationSeconds) {
      _seconds = _durationSeconds;
      _playbackState = EnginePlaybackState.paused;
      _timer?.cancel();
      _timer = null;
      _lastTickAt = null;
    }

    _emit();
  }

  void _emit() {
    final frame = (_seconds * config.fps).round();
    _controller.add(
      EngineStatusSnapshot(
        playbackState: _playbackState,
        position: EngineTimelinePosition(seconds: _seconds, frame: frame),
        isBuffering: false,
      ),
    );
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}
