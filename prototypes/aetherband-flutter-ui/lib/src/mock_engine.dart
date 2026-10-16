import 'dart:async';
import 'dart:math' as math;

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

/// UI-only simulation. This class does not open an audio device or produce sound.
abstract class EngineController {
  Stream<EngineTelemetry> get telemetry;
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
}

/// Demo implementation. A future native adapter can implement the same contract.
class MockEngineController implements EngineController {
  final StreamController<EngineTelemetry> _telemetry =
      StreamController<EngineTelemetry>.broadcast();

  Timer? _timer;
  bool _playing = false;
  double _position = 0;

  Stream<EngineTelemetry> get telemetry => _telemetry.stream;

  Future<void> play() async {
    _playing = true;
    _timer ??= Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (_playing) _position += 0.033;
      _emit();
    });
    _emit();
  }

  Future<void> stop() async {
    _playing = false;
    _position = 0;
    _emit();
  }

  void _emit() {
    if (_telemetry.isClosed) return;
    final time = _position * 2.1;
    final left = _playing ? 0.22 + 0.62 * math.sin(time).abs() : 0.0;
    final right = _playing ? 0.18 + 0.68 * math.sin(time + 1.1).abs() : 0.0;
    _telemetry.add(EngineTelemetry(
      playheadSeconds: _position,
      peakLeft: left.clamp(0.0, 1.0).toDouble(),
      peakRight: right.clamp(0.0, 1.0).toDouble(),
      isPlaying: _playing,
    ));
  }

  Future<void> dispose() async {
    _playing = false;
    _timer?.cancel();
    _timer = null;
    await _telemetry.close();
  }
}
