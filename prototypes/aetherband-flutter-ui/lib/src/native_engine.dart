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
typedef _SampleRateN = Int32 Function(Pointer<Void>, Pointer<Uint32>);
typedef _SampleRateD = int Function(Pointer<Void>, Pointer<Uint32>);
typedef _LoadTrackN = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint32>);
typedef _LoadTrackD = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint32>);
typedef _RemoveTrackN = Int32 Function(Pointer<Void>, Uint32);
typedef _RemoveTrackD = int Function(Pointer<Void>, int);
typedef _TrackCountN = Int32 Function(Pointer<Void>);
typedef _TrackCountD = int Function(Pointer<Void>);

const int _expectedApiVersion = 0x00000200;

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
  NativeEngineController._({
    required DynamicLibrary library,
    required Pointer<Void> handle,
    required _CommandD playNative,
    required _CommandD pauseNative,
    required _CommandD stopNative,
    required _CommandD destroyNative,
    required _PollD pollNative,
    required this.sampleRateHz,\n    required _LoadTrackD loadTrackNative,\n    required _RemoveTrackD removeTrackNative,\n    required _TrackCountD trackCountNative,
  })  : _library = library,
        _handle = handle,
        _playNative = playNative,
        _pauseNative = pauseNative,
        _stopNative = stopNative,
        _destroyNative = destroyNative,
        _pollNative = pollNative,\n        _loadTrackNative = loadTrackNative,\n        _removeTrackNative = removeTrackNative,\n        _trackCountNative = trackCountNative {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 33), (_) => _poll());
  }

  // Keep the native library loaded for as long as its function pointers/handle are used.
  // ignore: unused_field
  final DynamicLibrary _library;
  final Pointer<Void> _handle;
  final _CommandD _playNative;
  final _CommandD _pauseNative;
  final _CommandD _stopNative;
  final _CommandD _destroyNative;
  final _PollD _pollNative;\n  final _LoadTrackD _loadTrackNative;\n  final _RemoveTrackD _removeTrackNative;\n  final _TrackCountD _trackCountNative;
  final int sampleRateHz;
  final StreamController<EngineTelemetry> _telemetry = StreamController<EngineTelemetry>.broadcast();
  Timer? _pollTimer;
  bool _disposed = false;

  @override
  Stream<EngineTelemetry> get telemetry => _telemetry.stream;

  static Future<NativeEngineController> create() async {
    final library = _openLibrary();

    // Validate the ABI before calling any function that creates or mutates native
    // state. Resolve every required symbol before creating a handle so a missing
    // export cannot leak a newly-created engine.
    final version = library.lookupFunction<_VersionN, _VersionD>('daw_get_api_version');
    final actualVersion = version();
    if (actualVersion != _expectedApiVersion) {
      throw StateError(
        'Native API version mismatch: expected 0x${_expectedApiVersion.toRadixString(16)}, '
        'got 0x${actualVersion.toRadixString(16)}. Rebuild the Rust C ABI library.',
      );
    }

    final create = library.lookupFunction<_CreateN, _CreateD>('daw_engine_create');
    final play = library.lookupFunction<_CommandN, _CommandD>('daw_engine_play');
    final pause = library.lookupFunction<_CommandN, _CommandD>('daw_engine_pause');
    final stop = library.lookupFunction<_CommandN, _CommandD>('daw_engine_stop');
    final destroy = library.lookupFunction<_CommandN, _CommandD>('daw_engine_destroy');
    final poll = library.lookupFunction<_PollN, _PollD>('daw_engine_poll_telemetry');
    final getSampleRate = library.lookupFunction<_SampleRateN, _SampleRateD>('daw_engine_get_sample_rate');
    final loadTrack = library.lookupFunction<_LoadTrackN, _LoadTrackD>('daw_engine_load_track');
    final removeTrack = library.lookupFunction<_RemoveTrackN, _RemoveTrackD>('daw_engine_remove_track');
    final trackCount = library.lookupFunction<_TrackCountN, _TrackCountD>('daw_engine_get_track_count');

    final outHandle = calloc<Pointer<Void>>();
    try {
      final result = create(outHandle);
      if (result != 0) {
        throw StateError('Native engine creation failed (error $result). Check audio-device availability.');
      }
      final handle = outHandle.value;
      if (handle == nullptr) {
        throw StateError('Native engine creation returned a null handle.');
      }

      final outSampleRate = calloc<Uint32>();
      try {
        final sampleRateResult = getSampleRate(handle, outSampleRate);
        if (sampleRateResult != 0 || outSampleRate.value == 0) {
          destroy(handle);
          throw StateError(
            'Could not read the active native sample rate (error $sampleRateResult).',
          );
        }
        return NativeEngineController._(
          library: library,
          handle: handle,
          playNative: play,
          pauseNative: pause,
          stopNative: stop,
          destroyNative: destroy,
          pollNative: poll,
          sampleRateHz: outSampleRate.value,\n          loadTrackNative: loadTrack,\n          removeTrackNative: removeTrack,\n          trackCountNative: trackCount,
        );
      } finally {
        calloc.free(outSampleRate);
      }
    } finally {
      calloc.free(outHandle);
    }
  }

  static DynamicLibrary _openLibrary() {
    final names = Platform.isWindows
        ? <String>[
            'daw_core.dll',
            'target\\debug\\daw_core.dll',
            'target\\release\\daw_core.dll',
            '..\\..\\target\\debug\\daw_core.dll',
          ]
        : Platform.isMacOS
            ? <String>[
                'libdaw_core.dylib',
                'target/debug/libdaw_core.dylib',
                'target/release/libdaw_core.dylib',
                '../../target/debug/libdaw_core.dylib',
              ]
            : <String>[
                'libdaw_core.so',
                'target/debug/libdaw_core.so',
                'target/release/libdaw_core.so',
                '../../target/debug/libdaw_core.so',
              ];
    final errors = <String>[];
    for (final name in names) {
      try {
        return DynamicLibrary.open(name);
      } catch (error) {
        errors.add('$name: $error');
      }
    }
    throw StateError(
      'Native library not found. Build the daw_core_ffi Rust library. Tried: ${errors.join('; ')}',
    );
  }

  @override
  Future<int> loadTrack(String path) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    final nativePath = path.toNativeUtf8();
    final outTrackId = calloc<Uint32>();
    try {
      final result = _loadTrackNative(_handle, nativePath, outTrackId);
      if (result != 0) {
        throw StateError('Native audio import failed (error $result): $path');
      }
      return outTrackId.value;
    } finally {
      calloc.free(nativePath);
      calloc.free(outTrackId);
    }
  }

  @override
  Future<void> removeTrack(int trackId) async {
    _check('remove track', _removeTrackNative(_handle, trackId));
  }

  @override
  Future<int> getTrackCount() async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    final count = _trackCountNative(_handle);
    if (count < 0) throw StateError('Native track count query failed (error $count).');
    return count;
  }

  void _poll() {
    if (_disposed) return;
    final frame = calloc<_MeteringFrame>();
    try {
      final result = _pollNative(_handle, frame);
      if (result == 0) {
        final value = frame.ref;
        _telemetry.add(EngineTelemetry(
          playheadSeconds: value.playheadFrame / sampleRateHz,
          sampleRateHz: sampleRateHz,
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
