import 'dart:async';

class EngineTelemetry {
  const EngineTelemetry({
    required this.playheadSeconds,
    required this.sampleRateHz,
    required this.peakLeft,
    required this.peakRight,
    required this.isPlaying,
  });

  final double playheadSeconds;
  final int sampleRateHz;
  final double peakLeft;
  final double peakRight;
  final bool isPlaying;
}

abstract class EngineController {
  Stream<EngineTelemetry> get telemetry;
  Future<void> play();
  Future<void> pause();
  Future<void> stop();\n  Future<int> loadTrack(String path);\n  Future<void> removeTrack(int trackId);\n  Future<int> getTrackCount();
  Future<void> dispose();
}
