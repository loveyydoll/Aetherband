import 'dart:async';

class EngineTelemetry {
  const EngineTelemetry({
    required this.playheadSeconds,
    required this.peakLeft,
    required this.peakRight,
    required this.isPlaying,
  });

  final double playheadSeconds;
  final double peakLeft;
  final double peakRight;
  final bool isPlaying;
}

abstract class EngineController {
  Stream<EngineTelemetry> get telemetry;
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
}
