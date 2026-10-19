import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

/// Reads normalized peak buckets for PCM/IEEE-float WAV files off the UI
/// isolate. Other containers and compressed WAV subformats return null.
Future<List<double>?> loadWaveformPeaks(String path, {int bucketCount = 256}) {
  if (bucketCount <= 0 || bucketCount > 4096) {
    throw ArgumentError.value(bucketCount, 'bucketCount');
  }
  return Isolate.run(() => _loadWaveformPeaks(path, bucketCount));
}

Future<List<double>?> _loadWaveformPeaks(String path, int bucketCount) async {
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    final header = await _readExact(file, 12);
    if (header == null ||
        String.fromCharCodes(header.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(header.sublist(8, 12)) != 'WAVE') {
      return null;
    }

    var format = 0;
    var channels = 0;
    var sampleRate = 0;
    var blockAlign = 0;
    var bitsPerSample = 0;
    int? dataStart;
    int? dataBytes;
    while (await file.position() + 8 <= await file.length()) {
      final chunk = await _readExact(file, 8);
      if (chunk == null) return null;
      final id = String.fromCharCodes(chunk.sublist(0, 4));
      final size = ByteData.sublistView(chunk).getUint32(4, Endian.little);
      final start = await file.position();
      if (id == 'fmt ' && size >= 16) {
        final fmt = await _readExact(file, 16);
        if (fmt == null) return null;
        final bytes = ByteData.sublistView(fmt);
        format = bytes.getUint16(0, Endian.little);
        channels = bytes.getUint16(2, Endian.little);
        sampleRate = bytes.getUint32(4, Endian.little);
        blockAlign = bytes.getUint16(12, Endian.little);
        bitsPerSample = bytes.getUint16(14, Endian.little);
      } else if (id == 'data') {
        dataStart = start;
        dataBytes = size;
        break;
      }
      final next = start + size + (size.isOdd ? 1 : 0);
      if (next > await file.length()) return null;
      await file.setPosition(next);
    }

    if (dataStart == null ||
        dataBytes == null ||
        (format != 1 && format != 3) ||
        channels < 1 ||
        channels > 16 ||
        sampleRate <= 0 ||
        blockAlign <= 0 ||
        (format == 1 && !const {8, 16, 24, 32}.contains(bitsPerSample)) ||
        (format == 3 && !const {32, 64}.contains(bitsPerSample)) ||
        blockAlign < channels * (bitsPerSample ~/ 8)) {
      return null;
    }

    final frameCount = dataBytes ~/ blockAlign;
    if (frameCount <= 0) return null;
    final peaks = List<double>.filled(bucketCount, 0);
    await file.setPosition(dataStart);
    const targetReadBytes = 64 * 1024;
    final bytesPerSample = bitsPerSample ~/ 8;
    var frameIndex = 0;
    var remaining = frameCount * blockAlign;
    while (remaining >= blockAlign) {
      final chunkBytes =
          math.min(remaining, targetReadBytes - targetReadBytes % blockAlign);
      final chunk = await _readExact(file, chunkBytes);
      if (chunk == null) return null;
      final data = ByteData.sublistView(chunk);
      for (var offset = 0;
          offset + blockAlign <= chunk.length;
          offset += blockAlign) {
        final bucket =
            math.min(bucketCount - 1, frameIndex * bucketCount ~/ frameCount);
        var peak = 0.0;
        for (var channel = 0; channel < channels; channel++) {
          final value = _sampleMagnitude(
              data, offset + channel * bytesPerSample, format, bitsPerSample);
          if (value == null) return null;
          peak = math.max(peak, value);
        }
        peaks[bucket] = math.max(peaks[bucket], peak);
        frameIndex++;
      }
      remaining -= chunk.length;
    }
    return peaks;
  } on Object {
    return null;
  } finally {
    await file?.close();
  }
}

Future<Uint8List?> _readExact(RandomAccessFile file, int length) async {
  final result = await file.read(length);
  return result.length == length ? result : null;
}

double? _sampleMagnitude(ByteData data, int offset, int format, int bits) {
  double value;
  if (format == 3) {
    value = bits == 32
        ? data.getFloat32(offset, Endian.little)
        : data.getFloat64(offset, Endian.little);
    if (!value.isFinite) return null;
    return value.abs().clamp(0.0, 1.0).toDouble();
  }
  switch (bits) {
    case 8:
      value = (data.getUint8(offset) - 128) / 128.0;
    case 16:
      value = data.getInt16(offset, Endian.little) / 32768.0;
    case 24:
      var sample = data.getUint8(offset) |
          (data.getUint8(offset + 1) << 8) |
          (data.getUint8(offset + 2) << 16);
      if ((sample & 0x800000) != 0) sample -= 0x1000000;
      value = sample / 8388608.0;
    case 32:
      value = data.getInt32(offset, Endian.little) / 2147483648.0;
    default:
      return null;
  }
  return value.abs().clamp(0.0, 1.0).toDouble();
}
