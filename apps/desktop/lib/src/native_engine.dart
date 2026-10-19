import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'engine_controller.dart';

typedef _VersionN = Uint32 Function();
typedef _VersionD = int Function();
typedef _CreateN = Int32 Function(Pointer<Pointer<Void>>);
typedef _CreateD = int Function(Pointer<Pointer<Void>>);
typedef _CommandN = Int32 Function(Pointer<Void>);
typedef _CommandD = int Function(Pointer<Void>);
typedef _SeekN = Int32 Function(Pointer<Void>, Double);
typedef _SeekD = int Function(Pointer<Void>, double);
typedef _TrackRegionN = Int32 Function(Pointer<Void>, Uint32, Double, Double);
typedef _TrackRegionD = int Function(Pointer<Void>, int, double, double);
typedef _SequenceRegionN = Int32 Function(
    Pointer<Void>, Uint32, Double, Pointer<Int32>);
typedef _SequenceRegionD = int Function(
    Pointer<Void>, int, double, Pointer<Int32>);
typedef _PollN = Int32 Function(Pointer<Void>, Pointer<_MeteringFrame>);
typedef _PollD = int Function(Pointer<Void>, Pointer<_MeteringFrame>);
typedef _SampleRateN = Int32 Function(Pointer<Void>, Pointer<Uint32>);
typedef _SampleRateD = int Function(Pointer<Void>, Pointer<Uint32>);
typedef _DeviceCountN = Int32 Function(Pointer<Void>);
typedef _DeviceCountD = int Function(Pointer<Void>);
typedef _DeviceInfoN = Int32 Function(
    Pointer<Void>, Uint32, Pointer<_NativeDeviceInfo>);
typedef _DeviceInfoD = int Function(
    Pointer<Void>, int, Pointer<_NativeDeviceInfo>);
typedef _SelectDeviceN = Int32 Function(Pointer<Void>, Uint32);
typedef _SelectDeviceD = int Function(Pointer<Void>, int);
typedef _LoadTrackN = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Uint32>);
typedef _LoadTrackD = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Uint32>);
typedef _RemoveTrackN = Int32 Function(Pointer<Void>, Uint32);
typedef _RemoveTrackD = int Function(Pointer<Void>, int);
typedef _TrackFloatN = Int32 Function(Pointer<Void>, Uint32, Float);
typedef _TrackFloatD = int Function(Pointer<Void>, int, double);
typedef _TrackStartN = Int32 Function(Pointer<Void>, Uint32, Double);
typedef _TrackStartD = int Function(Pointer<Void>, int, double);
typedef _TrackMuteN = Int32 Function(Pointer<Void>, Uint32, Uint8);
typedef _TrackMuteD = int Function(Pointer<Void>, int, int);
typedef _SoloN = Int32 Function(Pointer<Void>, Uint32, Uint8);
typedef _SoloD = int Function(Pointer<Void>, int, int);
typedef _TrackCountN = Int32 Function(Pointer<Void>);
typedef _TrackCountD = int Function(Pointer<Void>);
typedef _TrackInfoN = Int32 Function(
    Pointer<Void>, Uint32, Pointer<_TrackInfo>);
typedef _TrackInfoD = int Function(Pointer<Void>, int, Pointer<_TrackInfo>);

typedef _SynthN = Int32 Function(Pointer<Void>, Uint32, Uint32, Float);
typedef _SynthD = int Function(Pointer<Void>, int, int, double);
typedef _TransportN = Int32 Function(Pointer<Void>, Float, Uint8, Uint8, Uint8);
typedef _TransportD = int Function(Pointer<Void>, double, int, int, int);
typedef _MasterN = Int32 Function(Pointer<Void>, Float);
typedef _MasterD = int Function(Pointer<Void>, double);
typedef _ExportN = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _ExportD = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _StartRecordingN = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _StartRecordingD = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _StopRecordingN = Int32 Function(
    Pointer<Void>, Pointer<_RecordingStats>);
typedef _StopRecordingD = int Function(Pointer<Void>, Pointer<_RecordingStats>);

const int _expectedApiVersion = 0x00000C00;

final class _TrackInfo extends Struct {
  @Uint64()
  external int totalFrames;
  @Uint32()
  external int sampleRate;
  @Uint32()
  external int channels;
}

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

final class _NativeDeviceInfo extends Struct {
  @Uint32()
  external int index;
  @Array(256)
  external Array<Uint8> name;
  @Uint32()
  external int defaultSampleRate;
  @Uint16()
  external int channels;
  @Uint8()
  external int isDefault;
}

final class _RecordingStats extends Struct {
  @Uint32()
  external int sampleRate;
  @Uint64()
  external int framesWritten;
  @Uint64()
  external int framesDropped;
}

/// The worker isolate owns every native pointer and serializes all calls,
/// including polling and destruction. Only commands/metadata cross isolates;
/// importing, restarting decoders and releasing hardware cannot block Flutter.
class NativeEngineController
    implements
        EngineController,
        PerformanceEngine,
        ExportEngine,
        AudioOutputEngine,
        AudioRecordingEngine,
        TransportSeekEngine,
        AudioRegionEngine,
        SequenceRegionEngine {
  NativeEngineController._() {
    _events.listen(_onEvent);
  }

  final ReceivePort _events = ReceivePort();
  final Completer<SendPort> _ready = Completer<SendPort>();
  final Map<int, Completer<Object?>> _pending = {};
  final StreamController<EngineTelemetry> _telemetry =
      StreamController.broadcast();
  SendPort? _commands;
  Isolate? _worker;
  int _nextRequest = 0;
  bool _disposed = false;
  bool _closed = false;
  Future<void>? _disposeFuture;

  static Future<NativeEngineController> create({String? libraryPath}) async {
    final controller = NativeEngineController._();
    try {
      controller._worker = await Isolate.spawn(
        _runNativeEngine,
        (controller._events.sendPort, libraryPath),
        onError: controller._events.sendPort,
        onExit: controller._events.sendPort,
        debugName: 'Aetherband native control',
      );
      controller._commands = await controller._ready.future;
      return controller;
    } catch (_) {
      controller._events.close();
      controller._worker?.kill();
      await controller._telemetry.close();
      rethrow;
    }
  }

  void _onEvent(Object? event) {
    if (_closed) return;
    if (event is SendPort) {
      _ready.complete(event);
    } else if (event is EngineTelemetry) {
      if (!_disposed) _telemetry.add(event);
    } else if (event is _PollingError) {
      if (!_disposed) _telemetry.addError(StateError(event.message));
    } else if (event is (int, Object?, String?)) {
      final (id, value, error) = event;
      final pending = _pending.remove(id);
      if (error == null) {
        pending?.complete(value);
      } else {
        pending?.completeError(StateError(error));
      }
    } else {
      final detail = event is List ? event.first : event;
      final error =
          StateError(detail?.toString() ?? 'Native engine worker exited.');
      if (!_ready.isCompleted) _ready.completeError(error);
      for (final pending in _pending.values) {
        pending.completeError(error);
      }
      _pending.clear();
      if (!_disposed && _ready.isCompleted && _commands != null) {
        _telemetry.addError(error);
      }
      _disposed = true;
      _closed = true;
      _events.close();
      unawaited(_telemetry.close());
    }
  }

  Future<T> _request<T>(String operation, [Object? argument]) {
    if (_disposed && operation != 'dispose') {
      return Future.error(StateError('Native engine has been disposed.'));
    }
    if (_closed || _commands == null) {
      return Future.error(StateError('Native engine worker is unavailable.'));
    }
    // Bound UI-side backlog as well as the Rust command queue. Disposal must
    // always be allowed so it can drain accepted work and release the handle.
    if (_pending.length >= 64 && operation != 'dispose') {
      return Future.error(StateError('Native engine is busy. Try again.'));
    }
    final id = _nextRequest++;
    final response = Completer<Object?>();
    _pending[id] = response;
    _commands!.send((id, operation, argument));
    return response.future.then((value) => value as T);
  }

  @override
  Stream<EngineTelemetry> get telemetry => _telemetry.stream;
  @override
  Future<void> play() => _request<void>('play');
  @override
  Future<void> synthEvent(int event, int key, double value) =>
      _request<void>('synth', (event, key, value));
  @override
  Future<void> configureTransport(
          double bpm, int beatsPerBar, bool metronome, bool sequence) =>
      _request<void>('transport', (bpm, beatsPerBar, metronome, sequence));
  @override
  Future<void> setMasterVolume(double gain) => _request<void>('master', gain);
  @override
  Future<void> exportWav(String path) {
    if (path.isEmpty || path.contains('\u0000')) {
      return Future.error(ArgumentError(
          'Export path must be nonempty and contain no NUL bytes.'));
    }
    return _request<void>('export', path);
  }

  @override
  Future<void> startRecording(String path) {
    if (path.isEmpty || path.contains('\u0000')) {
      return Future.error(ArgumentError(
          'Recording path must be nonempty and contain no NUL bytes.'));
    }
    return _request<void>('startRecording', path);
  }

  @override
  Future<AudioRecordingStats> stopRecording() =>
      _request<AudioRecordingStats>('stopRecording');

  @override
  Future<List<AudioOutputDevice>> getOutputDevices() =>
      _request<List<AudioOutputDevice>>('outputDevices');

  @override
  Future<void> selectOutputDevice(int index) =>
      _request<void>('selectOutputDevice', index);

  @override
  Future<void> pause() => _request<void>('pause');
  @override
  Future<void> stop() => _request<void>('stop');
  @override
  Future<void> seekSeconds(double seconds) {
    if (!seconds.isFinite || seconds < 0 || seconds > 86400) {
      return Future.error(ArgumentError.value(seconds, 'seconds'));
    }
    return _request<void>('seek', seconds);
  }

  @override
  Future<LoadedAudioTrack> loadTrack(String path) {
    if (path.isEmpty || path.contains('\u0000')) {
      return Future.error(ArgumentError(
          'Audio path must be nonempty and contain no NUL bytes.'));
    }
    return _request<LoadedAudioTrack>('load', path);
  }

  @override
  Future<void> removeTrack(int trackId) => _request<void>('remove', trackId);
  static void _checkUnitParameter(String name, double value) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(
          value, name, 'Must be a finite value in [0, 1]');
    }
  }

  @override
  Future<void> setTrackVolume(int trackId, double gain) {
    try {
      _checkUnitParameter('gain', gain);
    } on ArgumentError catch (error) {
      return Future<void>.error(error);
    }
    return _request<void>('volume', (trackId, gain));
  }

  @override
  Future<void> setTrackPan(int trackId, double pan) {
    try {
      _checkUnitParameter('pan', pan);
    } on ArgumentError catch (error) {
      return Future<void>.error(error);
    }
    return _request<void>('pan', (trackId, pan));
  }

  @override
  Future<void> setTrackStartSeconds(int trackId, double seconds) {
    if (!seconds.isFinite || seconds < 0 || seconds > 86400) {
      return Future.error(ArgumentError.value(seconds, 'seconds'));
    }
    return _request<void>('start', (trackId, seconds));
  }

  @override
  Future<void> setTrackRegionSeconds(
      int trackId, double sourceStartSeconds, double durationSeconds) {
    if (!sourceStartSeconds.isFinite ||
        sourceStartSeconds < 0 ||
        !durationSeconds.isFinite ||
        durationSeconds <= 0 ||
        sourceStartSeconds + durationSeconds > 86400) {
      return Future.error(ArgumentError('Invalid audio source region.'));
    }
    return _request<void>(
        'region', (trackId, sourceStartSeconds, durationSeconds));
  }

  @override
  Future<void> setSequenceRegion(
      int regionId, double startSeconds, List<int?> notes) {
    if (regionId <= 0 ||
        !startSeconds.isFinite ||
        startSeconds < 0 ||
        startSeconds > 86400 ||
        notes.length != 16 ||
        notes.any((note) => note != null && (note < 0 || note > 127))) {
      return Future.error(ArgumentError('Invalid HypnoSynth pattern region.'));
    }
    return _request<void>(
        'setSequenceRegion', (regionId, startSeconds, List<int?>.of(notes)));
  }

  @override
  Future<void> removeSequenceRegion(int regionId) =>
      _request<void>('removeSequenceRegion', regionId);

  @override
  Future<void> muteTrack(int trackId, bool muted) =>
      _request<void>('mute', (trackId, muted));

  @override
  Future<void> soloTrack(int trackId, bool solo) =>
      _request<void>('solo', (trackId, solo));

  @override
  Future<int> getTrackCount() => _request<int>('count');

  @override
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    try {
      if (!_closed) await _request<void>('dispose');
    } finally {
      _closed = true;
      _events.close();
      await _telemetry.close();
    }
  }
}

class _PollingError {
  const _PollingError(this.message);
  final String message;
}

Future<void> _runNativeEngine((SendPort, String?) configuration) async {
  final (events, libraryPath) = configuration;
  _NativeEngineSession? session;
  StreamSubscription<EngineTelemetry>? telemetry;
  final commands = ReceivePort();
  try {
    session = await _NativeEngineSession.create(libraryPath: libraryPath);
    telemetry = session.telemetry.listen(events.send, onError: (Object error) {
      events.send(_PollingError(error.toString()));
    });
    events.send(commands.sendPort);
    await for (final message in commands) {
      final (id, operation, argument) = message as (int, String, Object?);
      try {
        Object? result;
        switch (operation) {
          case 'synth':
            final (event, key, value) = argument as (int, int, double);
            await session.synthEvent(event, key, value);
          case 'transport':
            final (bpm, beatsPerBar, metronome, sequence) =
                argument as (double, int, bool, bool);
            await session.configureTransport(
                bpm, beatsPerBar, metronome, sequence);
          case 'master':
            await session.setMasterVolume(argument as double);
          case 'export':
            await session.exportWav(argument as String);
          case 'startRecording':
            await session.startRecording(argument as String);
          case 'stopRecording':
            result = await session.stopRecording();
          case 'outputDevices':
            result = await session.getOutputDevices();
          case 'selectOutputDevice':
            await session.selectOutputDevice(argument as int);
          case 'play':
            await session.play();
          case 'pause':
            await session.pause();
          case 'stop':
            await session.stop();
          case 'seek':
            await session.seekSeconds(argument as double);
          case 'load':
            result = await session.loadTrack(argument as String);
          case 'remove':
            await session.removeTrack(argument as int);
          case 'volume':
            final (trackId, gain) = argument as (int, double);
            await session.setTrackVolume(trackId, gain);
          case 'pan':
            final (trackId, pan) = argument as (int, double);
            await session.setTrackPan(trackId, pan);
          case 'start':
            final (trackId, seconds) = argument as (int, double);
            await session.setTrackStartSeconds(trackId, seconds);
          case 'region':
            final (trackId, sourceStart, duration) =
                argument as (int, double, double);
            await session.setTrackRegionSeconds(trackId, sourceStart, duration);
          case 'setSequenceRegion':
            final (regionId, startSeconds, notes) =
                argument as (int, double, List<int?>);
            await session.setSequenceRegion(regionId, startSeconds, notes);
          case 'removeSequenceRegion':
            await session.removeSequenceRegion(argument as int);
          case 'mute':
            final (trackId, muted) = argument as (int, bool);
            await session.muteTrack(trackId, muted);
          case 'solo':
            final (trackId, solo) = argument as (int, bool);
            await session.soloTrack(trackId, solo);
          case 'count':
            result = await session.getTrackCount();
          case 'dispose':
            await telemetry.cancel();
            await session.dispose();
          default:
            throw StateError('Unknown native operation: $operation');
        }
        events.send((id, result, null));
      } catch (error) {
        events.send((id, null, error.toString()));
      }
      if (operation == 'dispose') break;
    }
  } catch (error) {
    events.send(error.toString());
  } finally {
    commands.close();
    await telemetry?.cancel();
    await session?.dispose();
  }
}

/// Used only on the dedicated native control isolate. This object's pointers,
/// library, timer and handle never cross the isolate boundary.
class _NativeEngineSession
    implements
        EngineController,
        PerformanceEngine,
        ExportEngine,
        AudioOutputEngine,
        AudioRecordingEngine,
        TransportSeekEngine,
        AudioRegionEngine,
        SequenceRegionEngine {
  _NativeEngineSession._({
    required this.synthNative,
    required this.transportNative,
    required this.masterNative,
    required this.exportNative,
    required this.startRecordingNative,
    required this.stopRecordingNative,
    required DynamicLibrary library,
    required Pointer<Void> handle,
    required _CommandD playNative,
    required _CommandD pauseNative,
    required _CommandD stopNative,
    required _SeekD seekNative,
    required _TrackRegionD trackRegionNative,
    required _SequenceRegionD sequenceRegionNative,
    required _RemoveTrackD removeSequenceRegionNative,
    required _CommandD destroyNative,
    required _PollD pollNative,
    required this.sampleRateHz,
    required this.getSampleRateNative,
    required this.deviceCountNative,
    required this.deviceInfoNative,
    required this.selectDeviceNative,
    required _LoadTrackD loadTrackNative,
    required _RemoveTrackD removeTrackNative,
    required _TrackCountD trackCountNative,
    required _TrackInfoD trackInfoNative,
    required _TrackFloatD trackVolumeNative,
    required _TrackFloatD trackPanNative,
    required _TrackStartD trackStartNative,
    required _TrackMuteD muteTrackNative,
    required _SoloD soloTrackNative,
  })  : _library = library,
        _handle = handle,
        _playNative = playNative,
        _pauseNative = pauseNative,
        _stopNative = stopNative,
        _seekNative = seekNative,
        _trackRegionNative = trackRegionNative,
        _sequenceRegionNative = sequenceRegionNative,
        _removeSequenceRegionNative = removeSequenceRegionNative,
        _destroyNative = destroyNative,
        _pollNative = pollNative,
        _loadTrackNative = loadTrackNative,
        _removeTrackNative = removeTrackNative,
        _trackCountNative = trackCountNative,
        _trackInfoNative = trackInfoNative,
        _trackVolumeNative = trackVolumeNative,
        _trackPanNative = trackPanNative,
        _trackStartNative = trackStartNative,
        _muteTrackNative = muteTrackNative,
        _soloTrackNative = soloTrackNative {
    _pollTimer =
        Timer.periodic(const Duration(milliseconds: 33), (_) => _poll());
  }

  // Keep the native library loaded for as long as its function pointers/handle are used.
  // ignore: unused_field
  final DynamicLibrary _library;
  final Pointer<Void> _handle;
  final _CommandD _playNative;
  final _CommandD _pauseNative;
  final _CommandD _stopNative;
  final _SeekD _seekNative;
  final _TrackRegionD _trackRegionNative;
  final _SequenceRegionD _sequenceRegionNative;
  final _RemoveTrackD _removeSequenceRegionNative;
  final _CommandD _destroyNative;
  final _PollD _pollNative;
  final _LoadTrackD _loadTrackNative;
  final _RemoveTrackD _removeTrackNative;
  final _TrackCountD _trackCountNative;
  final _TrackInfoD _trackInfoNative;
  final _TrackFloatD _trackVolumeNative;
  final _TrackFloatD _trackPanNative;
  final _TrackStartD _trackStartNative;
  final _TrackMuteD _muteTrackNative;
  final _SoloD _soloTrackNative;
  final _SynthD synthNative;
  final _TransportD transportNative;
  final _MasterD masterNative;
  final _ExportD exportNative;
  final _StartRecordingD startRecordingNative;
  final _StopRecordingD stopRecordingNative;
  final _SampleRateD getSampleRateNative;
  final _DeviceCountD deviceCountNative;
  final _DeviceInfoD deviceInfoNative;
  final _SelectDeviceD selectDeviceNative;
  int sampleRateHz;
  final StreamController<EngineTelemetry> _telemetry =
      StreamController<EngineTelemetry>.broadcast();
  Timer? _pollTimer;
  bool _disposed = false;

  @override
  Stream<EngineTelemetry> get telemetry => _telemetry.stream;

  static Future<_NativeEngineSession> create({String? libraryPath}) async {
    final library =
        libraryPath == null ? _openLibrary() : DynamicLibrary.open(libraryPath);

    // Validate the ABI before calling any function that creates or mutates native
    // state. Resolve every required symbol before creating a handle so a missing
    // export cannot leak a newly-created engine.
    final version =
        library.lookupFunction<_VersionN, _VersionD>('daw_get_api_version');
    final actualVersion = version();
    if (actualVersion != _expectedApiVersion) {
      throw StateError(
        'Native API version mismatch: expected 0x${_expectedApiVersion.toRadixString(16)}, '
        'got 0x${actualVersion.toRadixString(16)}. Rebuild the Rust C ABI library.',
      );
    }

    final create =
        library.lookupFunction<_CreateN, _CreateD>('daw_engine_create');
    final play =
        library.lookupFunction<_CommandN, _CommandD>('daw_engine_play');
    final pause =
        library.lookupFunction<_CommandN, _CommandD>('daw_engine_pause');
    final stop =
        library.lookupFunction<_CommandN, _CommandD>('daw_engine_stop');
    final seek =
        library.lookupFunction<_SeekN, _SeekD>('daw_engine_seek_seconds');
    final trackRegion = library.lookupFunction<_TrackRegionN, _TrackRegionD>(
        'daw_engine_set_track_region_seconds');
    final sequenceRegion =
        library.lookupFunction<_SequenceRegionN, _SequenceRegionD>(
            'daw_engine_set_sequence_region');
    final removeSequenceRegion =
        library.lookupFunction<_RemoveTrackN, _RemoveTrackD>(
            'daw_engine_remove_sequence_region');
    final destroy =
        library.lookupFunction<_CommandN, _CommandD>('daw_engine_destroy');
    final poll =
        library.lookupFunction<_PollN, _PollD>('daw_engine_poll_telemetry');
    final getSampleRate = library.lookupFunction<_SampleRateN, _SampleRateD>(
        'daw_engine_get_sample_rate');
    final deviceCount = library.lookupFunction<_DeviceCountN, _DeviceCountD>(
        'daw_engine_get_device_count');
    final deviceInfo = library.lookupFunction<_DeviceInfoN, _DeviceInfoD>(
        'daw_engine_get_device_info');
    final selectDevice = library.lookupFunction<_SelectDeviceN, _SelectDeviceD>(
        'daw_engine_select_device');
    final loadTrack = library
        .lookupFunction<_LoadTrackN, _LoadTrackD>('daw_engine_load_track');
    final removeTrack = library.lookupFunction<_RemoveTrackN, _RemoveTrackD>(
        'daw_engine_remove_track');
    final trackCount = library.lookupFunction<_TrackCountN, _TrackCountD>(
        'daw_engine_get_track_count');
    final trackInfo = library
        .lookupFunction<_TrackInfoN, _TrackInfoD>('daw_engine_get_track_info');
    final trackVolume = library.lookupFunction<_TrackFloatN, _TrackFloatD>(
        'daw_engine_set_track_volume');
    final trackPan = library
        .lookupFunction<_TrackFloatN, _TrackFloatD>('daw_engine_set_track_pan');
    final trackStart = library.lookupFunction<_TrackStartN, _TrackStartD>(
        'daw_engine_set_track_start_seconds');
    final muteTrack = library
        .lookupFunction<_TrackMuteN, _TrackMuteD>('daw_engine_mute_track');
    final soloTrack =
        library.lookupFunction<_SoloN, _SoloD>('daw_engine_solo_track');

    final synth =
        library.lookupFunction<_SynthN, _SynthD>('daw_engine_synth_event');
    final transport = library.lookupFunction<_TransportN, _TransportD>(
        'daw_engine_configure_transport');
    final master = library
        .lookupFunction<_MasterN, _MasterD>('daw_engine_set_master_volume');
    final export =
        library.lookupFunction<_ExportN, _ExportD>('daw_engine_export_wav');
    final startRecording =
        library.lookupFunction<_StartRecordingN, _StartRecordingD>(
            'daw_engine_start_recording');
    final stopRecording =
        library.lookupFunction<_StopRecordingN, _StopRecordingD>(
            'daw_engine_stop_recording');
    final outHandle = calloc<Pointer<Void>>();
    try {
      final result = create(outHandle);
      if (result != 0) {
        throw StateError(
            'Native engine creation failed (error $result). Check audio-device availability.');
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
        return _NativeEngineSession._(
          synthNative: synth,
          transportNative: transport,
          masterNative: master,
          exportNative: export,
          startRecordingNative: startRecording,
          stopRecordingNative: stopRecording,
          library: library,
          handle: handle,
          playNative: play,
          pauseNative: pause,
          stopNative: stop,
          seekNative: seek,
          trackRegionNative: trackRegion,
          sequenceRegionNative: sequenceRegion,
          removeSequenceRegionNative: removeSequenceRegion,
          destroyNative: destroy,
          pollNative: poll,
          sampleRateHz: outSampleRate.value,
          getSampleRateNative: getSampleRate,
          deviceCountNative: deviceCount,
          deviceInfoNative: deviceInfo,
          selectDeviceNative: selectDevice,
          loadTrackNative: loadTrack,
          removeTrackNative: removeTrack,
          trackCountNative: trackCount,
          trackInfoNative: trackInfo,
          trackVolumeNative: trackVolume,
          trackPanNative: trackPan,
          trackStartNative: trackStart,
          muteTrackNative: muteTrack,
          soloTrackNative: soloTrack,
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
  Future<void> setSequenceRegion(
      int regionId, double startSeconds, List<int?> notes) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    if (notes.length != 16) throw ArgumentError.value(notes, 'notes');
    final nativeNotes = calloc<Int32>(16);
    try {
      for (var index = 0; index < 16; index++) {
        nativeNotes[index] = notes[index] ?? -1;
      }
      _check(
        'HypnoSynth pattern region',
        _sequenceRegionNative(_handle, regionId, startSeconds, nativeNotes),
      );
    } finally {
      calloc.free(nativeNotes);
    }
  }

  @override
  Future<void> removeSequenceRegion(int regionId) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check(
      'remove HypnoSynth pattern region',
      _removeSequenceRegionNative(_handle, regionId),
    );
  }

  @override
  Future<LoadedAudioTrack> loadTrack(String path) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    final nativePath = path.toNativeUtf8();
    final outTrackId = calloc<Uint32>();
    try {
      final result = _loadTrackNative(_handle, nativePath, outTrackId);
      if (result != 0) {
        throw StateError('Native audio import failed (error $result): $path');
      }
      final info = calloc<_TrackInfo>();
      try {
        final infoResult = _trackInfoNative(_handle, outTrackId.value, info);
        if (infoResult != 0) {
          final cleanupResult = _removeTrackNative(_handle, outTrackId.value);
          throw StateError(
              'Native track metadata failed (error $infoResult; rollback $cleanupResult).');
        }
        return LoadedAudioTrack(
          id: outTrackId.value,
          totalFrames: info.ref.totalFrames,
          sampleRateHz: info.ref.sampleRate,
          channels: info.ref.channels,
        );
      } finally {
        calloc.free(info);
      }
    } finally {
      calloc.free(nativePath);
      calloc.free(outTrackId);
    }
  }

  @override
  Future<void> removeTrack(int trackId) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check('remove track', _removeTrackNative(_handle, trackId));
  }

  @override
  Future<void> setTrackVolume(int trackId, double gain) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check('track volume', _trackVolumeNative(_handle, trackId, gain));
  }

  @override
  Future<void> setTrackPan(int trackId, double pan) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check('track pan', _trackPanNative(_handle, trackId, pan));
  }

  @override
  Future<void> setTrackStartSeconds(int trackId, double seconds) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check('track clip position', _trackStartNative(_handle, trackId, seconds));
  }

  @override
  Future<void> setTrackRegionSeconds(
      int trackId, double sourceStartSeconds, double durationSeconds) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check(
      'audio clip region',
      _trackRegionNative(_handle, trackId, sourceStartSeconds, durationSeconds),
    );
  }

  @override
  Future<void> muteTrack(int trackId, bool muted) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check('track mute', _muteTrackNative(_handle, trackId, muted ? 1 : 0));
  }

  @override
  Future<void> soloTrack(int trackId, bool solo) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check('track solo', _soloTrackNative(_handle, trackId, solo ? 1 : 0));
  }

  @override
  Future<int> getTrackCount() async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    final count = _trackCountNative(_handle);
    if (count < 0) {
      throw StateError('Native track count query failed (error $count).');
    }
    return count;
  }

  @override
  Future<void> synthEvent(int event, int key, double value) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check('HypnoSynth', synthNative(_handle, event, key, value));
  }

  @override
  Future<void> configureTransport(
      double bpm, int beatsPerBar, bool metronome, bool sequence) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check(
        'transport setup',
        transportNative(
            _handle, bpm, beatsPerBar, metronome ? 1 : 0, sequence ? 1 : 0));
  }

  @override
  Future<void> setMasterVolume(double gain) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check('master volume', masterNative(_handle, gain));
  }

  @override
  Future<void> exportWav(String path) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    final nativePath = path.toNativeUtf8();
    try {
      final result = exportNative(_handle, nativePath);
      if (result != 0) {
        throw StateError(
          'Mixdown export failed. Add imported audio or enable the HypnoSynth '
          'phrase, use clips with known duration, and choose a different output file.',
        );
      }
    } finally {
      calloc.free(nativePath);
    }
  }

  @override
  Future<void> startRecording(String path) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    final nativePath = path.toNativeUtf8();
    try {
      final result = startRecordingNative(_handle, nativePath);
      if (result != 0) {
        throw StateError(
          'Could not start Windows audio recording (error $result). Check microphone permissions, input device, and choose a new WAV filename.',
        );
      }
    } finally {
      calloc.free(nativePath);
    }
  }

  @override
  Future<AudioRecordingStats> stopRecording() async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    final stats = calloc<_RecordingStats>();
    try {
      final result = stopRecordingNative(_handle, stats);
      if (result != 0) {
        throw StateError(
            'Could not finish Windows audio recording (error $result).');
      }
      return AudioRecordingStats(
        sampleRateHz: stats.ref.sampleRate,
        framesWritten: stats.ref.framesWritten,
        framesDropped: stats.ref.framesDropped,
      );
    } finally {
      calloc.free(stats);
    }
  }

  @override
  Future<List<AudioOutputDevice>> getOutputDevices() async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    final count = deviceCountNative(_handle);
    if (count < 0) {
      throw StateError('Native output-device query failed (error $count).');
    }
    final info = calloc<_NativeDeviceInfo>();
    try {
      final devices = <AudioOutputDevice>[];
      for (var index = 0; index < count; index++) {
        final result = deviceInfoNative(_handle, index, info);
        _check('output-device metadata', result);
        final bytes = <int>[];
        for (var offset = 0; offset < 256; offset++) {
          final byte = info.ref.name[offset];
          if (byte == 0) break;
          bytes.add(byte);
        }
        devices.add(AudioOutputDevice(
          index: info.ref.index,
          name: utf8.decode(bytes, allowMalformed: true),
          sampleRateHz: info.ref.defaultSampleRate,
          channels: info.ref.channels,
          isDefault: info.ref.isDefault != 0,
        ));
      }
      return devices;
    } finally {
      calloc.free(info);
    }
  }

  @override
  Future<void> selectOutputDevice(int index) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check('output-device selection', selectDeviceNative(_handle, index));
    final outputRate = calloc<Uint32>();
    try {
      _check(
          'output sample-rate query', getSampleRateNative(_handle, outputRate));
      if (outputRate.value == 0) {
        throw StateError('Selected output reported an invalid sample rate.');
      }
      sampleRateHz = outputRate.value;
    } finally {
      calloc.free(outputRate);
    }
  }

  void _poll() {
    if (_disposed) return;
    final frame = calloc<_MeteringFrame>();
    try {
      final result = _pollNative(_handle, frame);
      if (result == 0) {
        final value = frame.ref;
        if (value.deviceErrorFlag != 0) {
          _pollTimer?.cancel();
          _telemetry.addError(StateError(
              'Audio output stopped. Check the Windows output device and reconnect.'));
          return;
        }
        _telemetry.add(EngineTelemetry(
          playheadSeconds: value.playheadFrame / sampleRateHz,
          sampleRateHz: sampleRateHz,
          peakLeft: value.peakLeft.clamp(0.0, 1.0).toDouble(),
          peakRight: value.peakRight.clamp(0.0, 1.0).toDouble(),
          isPlaying: value.isPlaying != 0,
        ));
      } else if (result < 0) {
        _pollTimer?.cancel();
        _telemetry.addError(
            StateError('Native telemetry polling failed (error $result).'));
      }
    } finally {
      calloc.free(frame);
    }
  }

  void _check(String operation, int result) {
    if (_disposed) throw StateError('Native engine has been disposed.');
    if (result != 0) {
      throw StateError('Native $operation failed (error $result).');
    }
  }

  @override
  Future<void> play() async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check('play', _playNative(_handle));
  }

  @override
  Future<void> pause() async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check('pause', _pauseNative(_handle));
  }

  @override
  Future<void> stop() async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check('stop', _stopNative(_handle));
  }

  @override
  Future<void> seekSeconds(double seconds) async {
    if (_disposed) throw StateError('Native engine has been disposed.');
    _check('transport seek', _seekNative(_handle, seconds));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    final result = _destroyNative(_handle);
    await _telemetry.close();
    if (result != 0) {
      throw StateError('Native engine destruction failed (error $result).');
    }
  }
}
