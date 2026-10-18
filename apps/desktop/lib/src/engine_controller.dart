import 'dart:async';

class LoadedAudioTrack {
  const LoadedAudioTrack({
    required this.id,
    required this.totalFrames,
    required this.sampleRateHz,
    required this.channels,
  });

  final int id;
  final int totalFrames;
  final int sampleRateHz;
  final int channels;

  double? get durationSeconds =>
      totalFrames > 0 && sampleRateHz > 0 ? totalFrames / sampleRateHz : null;
}

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
  Future<void> stop();
  Future<LoadedAudioTrack> loadTrack(String path);
  Future<void> removeTrack(int trackId);
  Future<int> getTrackCount();
  Future<void> dispose();
}
