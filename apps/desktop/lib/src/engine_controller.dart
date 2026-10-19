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

class AudioOutputDevice {
  const AudioOutputDevice({
    required this.index,
    required this.name,
    required this.sampleRateHz,
    required this.channels,
    required this.isDefault,
  });

  final int index;
  final String name;
  final int sampleRateHz;
  final int channels;
  final bool isDefault;
}

class AudioRecordingStats {
  const AudioRecordingStats({
    required this.sampleRateHz,
    required this.framesWritten,
    required this.framesDropped,
  });

  final int sampleRateHz;
  final int framesWritten;
  final int framesDropped;

  double get durationSeconds =>
      sampleRateHz > 0 ? framesWritten / sampleRateHz : 0;
}

abstract class EngineController {
  Stream<EngineTelemetry> get telemetry;
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<LoadedAudioTrack> loadTrack(String path);
  Future<void> removeTrack(int trackId);
  Future<void> setTrackVolume(int trackId, double gain);
  Future<void> setTrackPan(int trackId, double pan);
  Future<void> setTrackStartSeconds(int trackId, double seconds);
  Future<void> muteTrack(int trackId, bool muted);
  Future<void> soloTrack(int trackId, bool solo);
  Future<int> getTrackCount();
  Future<void> dispose();
}

/// Optional seeking capability, implemented by the Windows native engine.
abstract interface class TransportSeekEngine {
  Future<void> seekSeconds(double seconds);
}

/// Optional native performance capabilities, separate from imported-track I/O.
abstract interface class PerformanceEngine {
  Future<void> synthEvent(int event, int key, double value);
  Future<void> configureTransport(double bpm, bool metronome, bool sequence);
  Future<void> setMasterVolume(double gain);
}

abstract interface class ExportEngine {
  Future<void> exportWav(String path);
}

/// Optional native output-device discovery and selection.
abstract interface class AudioOutputEngine {
  Future<List<AudioOutputDevice>> getOutputDevices();
  Future<void> selectOutputDevice(int index);
}

/// Optional default-input capture support for Windows audio tracks.
abstract interface class AudioRecordingEngine {
  Future<void> startRecording(String path);
  Future<AudioRecordingStats> stopRecording();
}
