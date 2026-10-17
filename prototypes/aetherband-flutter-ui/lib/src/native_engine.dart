import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'engine_controller.dart';

typedef _VersionN = Uint32 Function();
typedef _VersionD = int Function();
typedef _CreateN = Int32 Function(Pointer<Pointer<Void>>);
typedef _CreateD = int Function(Pointer<Pointer<Void>>);
typedef _CommandN = Int32 Function(Pointer<Void>);
typedef _CommandD = int Function(Pointer<Void>);
typedef _PollN = Int32 Function(Pointer<Void>, Pointer<_MeteringFrame>);
typedef _PollD = int Function(Pointer<Void>, Pointer<_MeteringFrame>);

final class _MeteringFrame extends Struct {
  @Float()
  external double peakLeft;
  @Float()
  external double peakRight;
  @Float()
  external double rmsLeft;
  @Float()
  external double rmsRight;
  @Int64()
  external int playheadFrame;
  @Int64()
  external int totalDurationFrames;
  @Uint8()
  external int isPlaying;
  @Uint8()
  external int deviceErrorFlag;
}

/// Owns one native engine handle. Calls are serialized on the Flutter UI isolate;
/// all DSP, decoding, and audio callback work remains in Rust.
class NativeEngineController implements EngineController {
  NativeEngineController._(this._library, this._handle)
      : _version = _library.lookupFunction<_VersionN, _VersionD>('daw_get_api_version'),
        _playNative = _library.lookupFunction<_CommandN, _CommandD>('daw_engine_play'),
        _pauseNative = _library.lookupFunction<_CommandN, _CommandD>('daw_engine_pause'),
        _stopNative = _library.lookupFunction<_CommandN, _CommandD>('daw_engine_stop'),
        _destroyNative = _library.lookupFunction<_CommandN, _CommandD>('daw_engine_destroy'),
        _pollNative = _library.lookupFunction<_PollN, _PollD>('daw_engine_poll_telemetry') {
    final version = _version();
    if (version != 0x00000100) {
      _destroyNative(_handle);
      throw StateError('Native API version mismatch: expected 0x100, got 0x${version.toRadixString(16)}.');
    }
    _pollTimer = Timer.periodic(const Duration(milliseconds: 33), (_) => _poll());
  }

  final DynamicLibrary _library;
  final Pointer<Void> _handle;
  final _VersionD _version;
  final _CommandD _playNative;
  final _CommandD _pauseNative;
  final _CommandD _stopNative;
  final _CommandD _destroyNative;
  final _PollD _pollNative;
  final StreamController<EngineTelemetry> _telemetry = StreamController<EngineTelemetry>.broadcast();
  Timer? _pollTimer;
  bool _disposed = false;

  @override
  Stream<EngineTelemetry> get telemetry => _telemetry.stream;

  static Future<NativeEngineController> create() async {
    final library = _openLibrary();
    final create = library.lookupFunction<_CreateN, _CreateD>('daw_engine_create');
    final outHandle = calloc<Pointer<Void>>();
    try {
      final result = create(outHandle);
      if (result != 0) {
        throw StateError('Native engine creation failed (error $result). Check audio-device availability.');
      }
      if (outHandle.value == nullptr) {
        throw StateError('Native engine creation returned a null handle.');
      }
      return NativeEngineController._(library, outHandle.value);
    } finally {
      calloc.free(outHandle);
    }
  }

  static DynamicLibrary _openLibrary() {
    final names = Platform.isWindows
        ? <String>['daw_core.dll', 'target\\debug\\daw_core.dll', 'target\\release\\daw_core.dll', '..\\..\\target\\debug\\daw_core.dll']
        : Platform.isMacOS
            ? <String>['libdaw_core.dylib', 'target/debug/libdaw_core.dylib', 'target/release/libdaw_core.dylib', '../../target/debug/libdaw_core.dylib']
            : <String>['libdaw_core.so', 'target/debug/libdaw_core.so', 'target/release/libdaw_core.so', '../../target/debug/libdaw_core.so'];
    final errors = <String>[];
    for (final name in names) {
      try {
        return DynamicLibrary.open(name);
      } catch (error) {
        errors.add('$name: $error');
      }
    }
    throw StateError('Native library not found. Build the daw_core_ffi Rust library. Tried: ${errors.join('; ')}');
  }

  void _poll() {
    if (_disposed) return;
    final frame = calloc<_MeteringFrame>();
    try {
      final result = _pollNative(_handle, frame);
      if (result == 0) {
        final value = frame.ref;
        _telemetry.add(EngineTelemetry(
          // ABI currently omits the active sample rate; 48 kHz is an estimate for display.
          playheadSeconds: value.playheadFrame / 48000.0,
          peakLeft: value.peakLeft.clamp(0.0, 1.0).toDouble(),
          peakRight: value.peakRight.clamp(0.0, 1.0).toDouble(),
          isPlaying: value.isPlaying != 0,
        ));
      } else if (result < 0) {
        _telemetry.addError(StateError('Native telemetry polling failed (error $result).'));
      }
    } finally {
      calloc.free(frame);
    }
  }

  void _check(String operation, int result) {
    if (_disposed) throw StateError('Native engine has been disposed.');
    if (result != 0) throw StateError('Native $operation failed (error $result).');
  }

  @override
  Future<void> play() async => _check('play', _playNative(_handle));

  @override
  Future<void> pause() async => _check('pause', _pauseNative(_handle));

  @override
  Future<void> stop() async => _check('stop', _stopNative(_handle));

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    final result = _destroyNative(_handle);
    await _telemetry.close();
    if (result != 0) throw StateError('Native engine destruction failed (error $result).');
  }
}
