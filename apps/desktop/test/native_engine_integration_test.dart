import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:aetherband_desktop/src/engine_controller.dart';
import 'package:aetherband_desktop/src/native_engine.dart';

void main() {
  test(
      'missing native library reports startup failure without leaving a worker',
      () async {
    await expectLater(
      NativeEngineController.create(
              libraryPath: 'aetherband_missing_test_library')
          .timeout(const Duration(seconds: 5)),
      throwsA(isA<StateError>()),
    );
  });

  final libraryPath = Platform.environment['AETHERBAND_NATIVE_LIBRARY'];
  test('native import, telemetry, transport, removal and queued shutdown',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('aetherband-native-');
    final file = File('${directory.path}/táké-音.wav');
    await file.writeAsBytes(_waveFile());
    final engine =
        await NativeEngineController.create(libraryPath: libraryPath);
    try {
      final outputDevices = await engine.getOutputDevices();
      expect(outputDevices, isNotEmpty);
      expect(outputDevices.any((device) => device.isDefault), isTrue);
      expect(outputDevices.every((device) => device.name.isNotEmpty), isTrue);
      final defaultOutput =
          outputDevices.firstWhere((device) => device.isDefault);
      final pattern = List<int?>.filled(16, null)..[0] = 60;
      await expectLater(
          engine.configureTransport(124, 8, false, true), throwsStateError);
      await engine.configureTransport(120, 4, false, false);
      await engine.setSequenceRegion(77, 0.1, pattern);
      await engine.play();
      final arrangedNote = await engine.telemetry
          .firstWhere((frame) =>
              frame.isPlaying &&
              frame.playheadSeconds >= 0.1 &&
              (frame.peakLeft > 0 || frame.peakRight > 0))
          .timeout(const Duration(seconds: 10));
      expect(arrangedNote.playheadSeconds, greaterThanOrEqualTo(0.1));
      await engine.stop();
      await engine.removeSequenceRegion(77);
      await engine.configureTransport(124, 3, false, true);
      await engine.synthEvent(2, 1, 0);
      await engine.synthEvent(3, 0, 0.9);
      await engine.synthEvent(6, 0, 0.6);
      await engine.synthEvent(7, 0, 0.75);
      await engine.synthEvent(8, 0, 0);
      await engine.synthEvent(9, 0, 0);
      await engine.synthEvent(5, 0, -1); // Rest on step 1.
      await engine.synthEvent(5, 1, 60); // C4 on step 2.
      await engine.setMasterVolume(0.3);
      await engine.selectOutputDevice(defaultOutput.index);
      expect(defaultOutput.sampleRateHz, greaterThan(0));

      // The replacement processor must retain the edited sequence, preset, macro,
      // tempo, and master configuration instead of coming up with defaults.
      await engine.play();
      final synthAfterSwitch = await engine.telemetry
          .firstWhere((frame) => frame.isPlaying && frame.peakLeft > 0)
          .timeout(const Duration(seconds: 10));
      expect(synthAfterSwitch.playheadSeconds, greaterThan(0));
      await engine.stop();
      await engine.synthEvent(7, 0, 1.0);
      await engine.play();
      final hardRight = await engine.telemetry
          .firstWhere((frame) =>
              frame.isPlaying &&
              frame.peakRight > 0 &&
              frame.peakLeft < 0.000001)
          .timeout(const Duration(seconds: 10));
      expect(hardRight.peakLeft, lessThan(0.000001));
      expect(hardRight.peakRight, greaterThan(0));
      await engine.stop();
      await engine.synthEvent(7, 0, 0.75);
      await engine.configureTransport(92, 4, false, false);
      await engine.synthEvent(2, 0, 0);
      await engine.synthEvent(3, 0, 0.42);
      await engine.setMasterVolume(0.8);

      final track = await engine.loadTrack(file.path);
      expect(track.totalFrames, 88200);
      expect(track.sampleRateHz, 44100);
      expect(track.channels, 1);
      expect(track.durationSeconds, 2);
      expect(await engine.getTrackCount(), 1);

      // Mixer commands exercise the real Dart isolate -> C ABI -> Rust path.
      await expectLater(
          engine.setTrackVolume(track.id, double.nan), throwsArgumentError);
      await expectLater(
          engine.setTrackPan(track.id, double.infinity), throwsArgumentError);
      await engine.setTrackVolume(track.id, 0.4);
      await engine.setTrackPan(track.id, 0.75);
      await engine.muteTrack(track.id, true);
      await engine.play();
      final muted = await engine.telemetry
          .firstWhere((frame) =>
              frame.isPlaying &&
              frame.playheadSeconds > 0 &&
              frame.peakLeft == 0 &&
              frame.peakRight == 0)
          .timeout(const Duration(seconds: 5));
      expect(muted.isPlaying, isTrue);
      await engine.muteTrack(track.id, false);
      await engine.telemetry
          .firstWhere((frame) => frame.isPlaying && frame.peakLeft > 0)
          .timeout(const Duration(seconds: 5));
      await engine.seekSeconds(1.25);
      final sought = await engine.telemetry
          .firstWhere(
              (frame) => frame.isPlaying && frame.playheadSeconds >= 1.25)
          .timeout(const Duration(seconds: 5));
      expect(sought.playheadSeconds, greaterThanOrEqualTo(1.25));
      await engine.stop();

      // Region edits rebuild the decoder from the requested source offset and
      // bound both live playback and offline rendering to the chosen duration.
      await (engine as AudioRegionEngine)
          .setTrackRegionSeconds(track.id, 0.5, 1.0);
      await engine.play();
      await engine.telemetry
          .firstWhere((frame) => frame.isPlaying && frame.peakLeft > 0)
          .timeout(const Duration(seconds: 5));
      await engine.stop();

      // Offline rendering traverses the real Dart isolate -> C ABI -> Rust
      // path while the same session remains loaded.
      final mixdown = File('${directory.path}/mixdown.wav');
      await engine.exportWav(mixdown.path);
      final mixedBytes = await mixdown.readAsBytes();
      expect(String.fromCharCodes(mixedBytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(mixedBytes.sublist(8, 12)), 'WAVE');
      expect(ByteData.sublistView(mixedBytes).getUint16(22, Endian.little), 2);
      expect(ByteData.sublistView(mixedBytes).getUint16(32, Endian.little), 6);
      expect(ByteData.sublistView(mixedBytes).getUint16(34, Endian.little), 24);
      final exportRate =
          ByteData.sublistView(mixedBytes).getUint32(24, Endian.little);
      final exportFrames =
          ByteData.sublistView(mixedBytes).getUint32(40, Endian.little) ~/ 6;
      expect(exportFrames / exportRate, closeTo(1.0, 1 / exportRate));
      expect(mixedBytes.sublist(44).any((sample) => sample != 0), isTrue);
      expect((await engine.telemetry.first).playheadSeconds, 0);

      await engine.play();
      final playing = await engine.telemetry
          .firstWhere((frame) => frame.isPlaying && frame.peakLeft > 0)
          .timeout(const Duration(seconds: 10));
      expect(playing.playheadSeconds, greaterThan(0));
      await engine.pause();
      final paused = await engine.telemetry
          .firstWhere((frame) => !frame.isPlaying)
          .timeout(const Duration(seconds: 5));
      expect(paused.peakLeft, 0);
      await engine.play();
      await engine.telemetry
          .firstWhere((frame) => frame.isPlaying && frame.peakLeft > 0)
          .timeout(const Duration(seconds: 5));
      await engine.stop();
      await engine.telemetry
          .firstWhere((frame) =>
              !frame.isPlaying &&
              frame.playheadSeconds == 0 &&
              frame.peakLeft == 0)
          .timeout(const Duration(seconds: 5));
      await engine.play();
      await engine.telemetry
          .firstWhere((frame) => frame.isPlaying && frame.peakLeft > 0)
          .timeout(const Duration(seconds: 5));
      await engine.stop();
      await engine.removeTrack(track.id);
      expect(await engine.getTrackCount(), 0);
      await expectLater(
          engine.removeTrack(track.id), throwsA(isA<StateError>()));
      await expectLater(engine.loadTrack('${directory.path}/missing.wav'),
          throwsA(isA<StateError>()));
      expect(await engine.getTrackCount(), 0);
      await expectLater(engine.loadTrack('bad\u0000path'), throwsArgumentError);

      final requests = List.generate(64, (_) => engine.getTrackCount());
      await expectLater(engine.getTrackCount(), throwsA(isA<StateError>()));
      expect(await Future.wait(requests), everyElement(0));

      // Destruction queues behind an accepted import, while new requests are
      // rejected immediately. No handle is destroyed during a file operation.
      final pendingImport = engine.loadTrack(file.path);
      final disposal = engine.dispose();
      await expectLater(engine.play(), throwsA(isA<StateError>()));
      expect((await pendingImport).durationSeconds, 2);
      await disposal;
      await engine.dispose();
      await expectLater(engine.getTrackCount(), throwsA(isA<StateError>()));
    } finally {
      await engine.dispose();
      await directory.delete(recursive: true);
    }
  },
      skip: libraryPath == null
          ? 'Set AETHERBAND_NATIVE_LIBRARY to a built native library; requires an audio output device.'
          : false);
}

Uint8List _waveFile() {
  const rate = 44100;
  const frames = rate * 2;
  final data = ByteData(44 + frames * 2);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  text(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, frames * 2, Endian.little);
  for (var i = 0; i < frames; i++) {
    data.setInt16(44 + i * 2,
        (300 * math.sin(i * 440 * 2 * math.pi / rate)).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}
