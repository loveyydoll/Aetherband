import 'dart:convert';
import 'performance_settings.dart';
import 'dart:io';
import 'dart:isolate';

/// The first persistent Aetherband session format stores *real imported audio*.
/// Demo clips, unsupported timeline edits, plugins and recording are excluded.
/// Native engine track IDs are never serialized.
class SavedAudioTrack {
  const SavedAudioTrack({
    required this.id,
    required this.name,
    required this.sourceUri,
    required this.gain,
    required this.pan,
    required this.muted,
    this.solo = false,
  });

  final String id;
  final String name;
  final String sourceUri;
  final double gain;
  final double pan;
  final bool muted;
  final bool solo;

  String get sourcePath => File.fromUri(_sourceFileUri(sourceUri)).path;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'sourceUri': sourceUri,
        'gain': gain,
        'pan': pan,
        'muted': muted,
        'solo': solo,
      };

  factory SavedAudioTrack.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Session track must be an object.');
    }
    final id = _boundedText(value['id'], 'track id', 128);
    final name = _boundedText(value['name'], 'track name', 120);
    final sourceUri =
        _boundedText(value['sourceUri'], 'audio source URI', 4096);
    _sourceFileUri(sourceUri);
    final gain = _unitNumber(value['gain'], 'gain');
    final pan = _unitNumber(value['pan'], 'pan');
    final muted = value['muted'];
    final solo = value['solo'] ?? false;
    if (muted is! bool || solo is! bool) {
      throw const FormatException('Track muted must be a boolean.');
    }
    return SavedAudioTrack(
      id: id,
      name: name,
      sourceUri: sourceUri,
      gain: gain,
      pan: pan,
      muted: muted,
      solo: solo,
    );
  }
}

class AudioSessionDocument {
  const AudioSessionDocument(
      {required this.title,
      required this.tracks,
      this.performance = const PerformanceSettings()});

  static const String format = 'aetherband-session';
  static const int schemaVersion = 2;
  static const int maxTracks = 64;

  final String title;
  final List<SavedAudioTrack> tracks;
  final PerformanceSettings performance;

  Map<String, Object?> toJson() => {
        'format': format,
        'schemaVersion': schemaVersion,
        'title': title,
        'performance': performance.toJson(),
        'tracks': tracks.map((track) => track.toJson()).toList(),
      };

  factory AudioSessionDocument.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Session document must be an object.');
    }
    if (value['format'] != format) {
      throw const FormatException('Not an Aetherband audio session.');
    }
    if (value['schemaVersion'] != 1 &&
        value['schemaVersion'] != schemaVersion) {
      throw FormatException(
        'Unsupported session version: ${value['schemaVersion']}.',
      );
    }
    final title = _boundedText(value['title'], 'session title', 120);
    final data = value['tracks'];
    if (data is! List || data.length > maxTracks) {
      throw const FormatException('Invalid session track list or track limit.');
    }
    final tracks = data.map(SavedAudioTrack.fromJson).toList(growable: false);
    final ids = tracks.map((track) => track.id).toSet();
    if (ids.length != tracks.length) {
      throw const FormatException('Duplicate persistent track IDs.');
    }
    return AudioSessionDocument(
        title: title,
        tracks: tracks,
        performance: value['schemaVersion'] == 1
            ? const PerformanceSettings()
            : PerformanceSettings.fromJson(value['performance']));
  }
}

String _boundedText(Object? value, String name, int limit) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > limit ||
      value.contains('\u0000')) {
    throw FormatException('Invalid $name.');
  }
  return value;
}

double _unitNumber(Object? value, String name) {
  if (value is! num || !value.isFinite || value < 0 || value > 1) {
    throw FormatException('Invalid $name; expected a number from 0 to 1.');
  }
  return value.toDouble();
}

Uri _sourceFileUri(String text) {
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme != 'file' ||
      uri.host.isNotEmpty ||
      !uri.path.startsWith('/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException(
        'Audio sources must use absolute local file URIs.');
  }
  return uri;
}

/// Project I/O occurs in worker isolates. Write a flushed temporary document
/// in the same folder, then replace the destination using a recoverable backup.
/// A missing target can be recovered from the .bak file after an interrupted save.
class AudioSessionStore {
  const AudioSessionStore();

  static const int _maximumDocumentBytes = 2 * 1024 * 1024;

  Future<void> save(String path, AudioSessionDocument document) async {
    // Validate the outgoing representation too, not only untrusted inputs.
    AudioSessionDocument.fromJson(document.toJson());
    final payload =
        const JsonEncoder.withIndent('  ').convert(document.toJson());
    if (utf8.encode(payload).length > _maximumDocumentBytes) {
      throw const FormatException('Session exceeds the maximum file size.');
    }
    await Isolate.run(() => _saveOnWorker(path, payload));
  }

  Future<AudioSessionDocument> open(String path) =>
      Isolate.run(() => _openOnWorker(path));

  static Future<AudioSessionDocument> _openOnWorker(String path) async {
    var file = File(path).absolute;
    if (!await file.exists()) {
      final backup = File('${file.path}.bak');
      if (!await backup.exists()) {
        throw FileSystemException('Session file does not exist.', file.path);
      }
      file = backup;
    }
    if (await file.length() > _maximumDocumentBytes) {
      throw const FormatException('Session file is too large.');
    }
    final document =
        AudioSessionDocument.fromJson(jsonDecode(await file.readAsString()));
    for (final track in document.tracks) {
      final audio = File(track.sourcePath);
      if (!await audio.exists()) {
        throw FileSystemException(
          'Missing source audio for "${track.name}". The current session was not replaced.',
          audio.path,
        );
      }
    }
    return document;
  }

  static Future<void> _saveOnWorker(String path, String payload) async {
    final target = File(path).absolute;
    if (!await target.parent.exists()) {
      throw FileSystemException(
          'Project directory does not exist.', target.parent.path);
    }
    final temporary =
        File('${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
    final backup = File('${target.path}.bak');
    var movedOriginal = false;
    try {
      await temporary.writeAsString(payload, flush: true);
      if (await target.exists()) {
        if (await backup.exists()) {
          await backup.delete();
        }
        await target.rename(backup.path);
        movedOriginal = true;
      }
      try {
        await temporary.rename(target.path);
      } catch (_) {
        if (movedOriginal && !await target.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }
      // The new document is safely present. A failed backup cleanup must not
      // turn a successful save into a reported failure.
      if (movedOriginal) {
        try {
          await backup.delete();
        } on FileSystemException {
          // A harmless stale backup can be cleaned up on the next save.
        }
      }
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }
}
