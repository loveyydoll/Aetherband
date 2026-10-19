import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherband_desktop/src/waveform_loader.dart';

void main() {
  late Directory directory;

  setUp(() async => directory =
      await Directory.systemTemp.createTemp('aetherband-waveform-test-'));
  tearDown(() async => directory.delete(recursive: true));

  test('returns measured PCM peaks in normalized buckets', () async {
    final path = '${directory.path}${Platform.pathSeparator}signal.wav';
    await File(path).writeAsBytes(_pcm16Wave([0, 8192, -16384, 32767]));

    final peaks = await loadWaveformPeaks(path, bucketCount: 4);

    expect(peaks, hasLength(4));
    expect(peaks![0], 0);
    expect(peaks[1], closeTo(0.25, 0.0001));
    expect(peaks[2], closeTo(0.5, 0.0001));
    expect(peaks[3], closeTo(32767 / 32768, 0.0001));
  });

  test('returns unavailable for non-WAV and malformed input', () async {
    final path = '${directory.path}${Platform.pathSeparator}compressed.mp3';
    await File(path).writeAsString('not PCM WAV data');

    expect(await loadWaveformPeaks(path), isNull);
  });

  test('rejects unreasonable bucket counts', () {
    expect(() => loadWaveformPeaks('unused.wav', bucketCount: 0),
        throwsArgumentError);
    expect(() => loadWaveformPeaks('unused.wav', bucketCount: 4097),
        throwsArgumentError);
  });
}

Uint8List _pcm16Wave(List<int> samples) {
  const channels = 1;
  const sampleRate = 44100;
  const bits = 16;
  final bytes = ByteData(44 + samples.length * 2);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * channels * bits ~/ 8, Endian.little);
  bytes.setUint16(32, channels * bits ~/ 8, Endian.little);
  bytes.setUint16(34, bits, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}
