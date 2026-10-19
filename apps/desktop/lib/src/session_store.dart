import 'dart:convert';
import 'performance_settings.dart';
import 'dart:io';
import 'dart:isolate';

/// Aetherband sessions store imported audio, HypnoSynth track state, clip
/// positions and performance settings. Demo clips, plugins and recordings are excluded.
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
    this.startSeconds = 0,
    this.regions = const <SavedAudioRegion>[],
  });

  final String id;
  final String name;
  final String sourceUri;
  final double gain;
  final double pan;
  final bool muted;
  final bool solo;
  final double startSeconds;
  final List<SavedAudioRegion> regions;

  List<SavedAudioRegion> get effectiveRegions => regions.isEmpty
      ? <SavedAudioRegion>[
          SavedAudioRegion(
            id: '$id-clip',
            startSeconds: startSeconds,
          ),
        ]
      : regions;

  String get sourcePath => File.fromUri(_sourceFileUri(sourceUri)).path;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'sourceUri': sourceUri,
        'gain': gain,
        'pan': pan,
        'muted': muted,
        'solo': solo,
        'startSeconds': startSeconds,
        'regions': effectiveRegions.map((region) => region.toJson()).toList(),
      };

  factory SavedAudioTrack.fromJson(Object? value, {bool hasRegions = false}) {
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
    final startSeconds = value['startSeconds'] ?? 0;
    if (muted is! bool ||
        solo is! bool ||
        startSeconds is! num ||
        !startSeconds.isFinite ||
        startSeconds < 0 ||
        startSeconds > 86400) {
      throw const FormatException(
          'Track mute/solo flags or clip start time are invalid.');
    }
    final regions = hasRegions
        ? _regionsFromJson(value['regions'], id)
        : <SavedAudioRegion>[
            SavedAudioRegion(
              id: '$id-clip',
              startSeconds: startSeconds.toDouble(),
            ),
          ];
    return SavedAudioTrack(
      id: id,
      name: name,
      sourceUri: sourceUri,
      gain: gain,
      pan: pan,
      muted: muted,
      solo: solo,
      startSeconds: startSeconds.toDouble(),
      regions: regions,
    );
  }
}

class SavedAudioRegion {
  const SavedAudioRegion({
    required this.id,
    required this.startSeconds,
    this.sourceStartSeconds = 0,
    this.durationSeconds,
  });

  final String id;
  final double startSeconds;
  final double sourceStartSeconds;
  final double? durationSeconds;

  Map<String, Object?> toJson() => {
        'id': id,
        'startSeconds': startSeconds,
        'sourceStartSeconds': sourceStartSeconds,
        'durationSeconds': durationSeconds,
      };

  factory SavedAudioRegion.fromJson(Object? value, String trackId) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Audio region must be an object.');
    }
    final id = _boundedText(value['id'], 'region id', 160);
    final start = value['startSeconds'];
    final sourceStart = value['sourceStartSeconds'] ?? 0;
    final duration = value['durationSeconds'];
    if (start is! num ||
        !start.isFinite ||
        start < 0 ||
        start > 86400 ||
        sourceStart is! num ||
        !sourceStart.isFinite ||
        sourceStart < 0 ||
        sourceStart > 86400 ||
        (duration != null &&
            (duration is! num ||
                !duration.isFinite ||
                duration <= 0 ||
                duration > 86400)) ||
        !id.startsWith('$trackId-')) {
      throw const FormatException('Audio region position or range is invalid.');
    }
    return SavedAudioRegion(
      id: id,
      startSeconds: start.toDouble(),
      sourceStartSeconds: sourceStart.toDouble(),
      durationSeconds: (duration as num?)?.toDouble(),
    );
  }
}

/// A HypnoSynth arrangement track. Voice settings remain session-wide; each
/// track's playable 16-step pattern regions are saved with their positions.
class SavedInstrumentTrack {
  const SavedInstrumentTrack({
    required this.id,
    required this.name,
    this.gain = 0.8,
    this.pan = 0.5,
    this.muted = false,
    this.solo = false,
    this.regions = const <SavedSequenceRegion>[],
  });

  final String id;
  final String name;
  final double gain;
  final double pan;
  final bool muted;
  final bool solo;
  final List<SavedSequenceRegion> regions;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'gain': gain,
        'pan': pan,
        'muted': muted,
        'solo': solo,
        'regions': regions.map((region) => region.toJson()).toList(),
      };

  factory SavedInstrumentTrack.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Instrument track must be an object.');
    }
    final muted = value['muted'] ?? false;
    final solo = value['solo'] ?? false;
    if (muted is! bool || solo is! bool) {
      throw const FormatException('Instrument mute/solo flags are invalid.');
    }
    return SavedInstrumentTrack(
      id: _boundedText(value['id'], 'track id', 128),
      name: _boundedText(value['name'], 'track name', 120),
      gain:
          value.containsKey('gain') ? _unitNumber(value['gain'], 'gain') : 0.8,
      pan: value.containsKey('pan') ? _unitNumber(value['pan'], 'pan') : 0.5,
      muted: muted,
      solo: solo,
      regions: value['regions'] == null
          ? const <SavedSequenceRegion>[]
          : _sequenceRegionsFromJson(value['regions']),
    );
  }
}

class SavedSequenceRegion {
  const SavedSequenceRegion({
    required this.id,
    required this.startSeconds,
    required this.notes,
  });

  final int id;
  final double startSeconds;
  final List<int?> notes;

  Map<String, Object?> toJson() => {
        'id': id,
        'startSeconds': startSeconds,
        'notes': notes,
      };
}

class AudioSessionDocument {
  const AudioSessionDocument(
      {required this.title,
      required this.tracks,
      this.instrumentTracks = const <SavedInstrumentTrack>[],
      this.performance = const PerformanceSettings()});

  static const String format = 'aetherband-session';
  static const int schemaVersion = 6;
  static const int maxTracks = 64;

  final String title;
  final List<SavedAudioTrack> tracks;
  final List<SavedInstrumentTrack> instrumentTracks;
  final PerformanceSettings performance;

  Map<String, Object?> toJson() => {
        'format': format,
        'schemaVersion': schemaVersion,
        'title': title,
        'performance': performance.toJson(),
        'tracks': tracks.map((track) => track.toJson()).toList(),
        'instrumentTracks':
            instrumentTracks.map((track) => track.toJson()).toList(),
      };

  factory AudioSessionDocument.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Session document must be an object.');
    }
    if (value['format'] != format) {
      throw const FormatException('Not an Aetherband audio session.');
    }
    if (value['schemaVersion'] != 1 &&
        value['schemaVersion'] != 2 &&
        value['schemaVersion'] != 3 &&
        value['schemaVersion'] != 4 &&
        value['schemaVersion'] != 5 &&
        value['schemaVersion'] != schemaVersion) {
      throw FormatException(
        'Unsupported session version: ${value['schemaVersion']}.',
      );
    }
    final title = _boundedText(value['title'], 'session title', 120);
    final data = value['tracks'];
    final instrumentsData =
        value['schemaVersion'] == 5 || value['schemaVersion'] == 6
            ? value['instrumentTracks']
            : const <Object?>[];
    if (data is! List ||
        instrumentsData is! List ||
        instrumentsData.length > 1 ||
        data.length + instrumentsData.length > maxTracks) {
      throw const FormatException('Invalid session track list or track limit.');
    }
    final hasRegions = value['schemaVersion'] == 4 ||
        value['schemaVersion'] == 5 ||
        value['schemaVersion'] == 6;
    final tracks = data
        .map((track) => SavedAudioTrack.fromJson(track, hasRegions: hasRegions))
        .toList(growable: false);
    final instrumentTracks = instrumentsData
        .map(SavedInstrumentTrack.fromJson)
        .toList(growable: false);
    final ids = tracks.map((track) => track.id).toSet();
    ids.addAll(instrumentTracks.map((track) => track.id));
    final regionIds = tracks
        .expand((track) => track.effectiveRegions)
        .map((region) => region.id)
        .toList();
    if (ids.length != tracks.length + instrumentTracks.length ||
        regionIds.toSet().length != regionIds.length ||
        regionIds.any(ids.contains) ||
        regionIds.length > maxTracks) {
      throw const FormatException(
          'Duplicate track/region IDs or track limit exceeded.');
    }
    final sequenceIds = instrumentTracks
        .expand((track) => track.regions)
        .map((region) => region.id)
        .toList();
    if (sequenceIds.toSet().length != sequenceIds.length ||
        sequenceIds.any((id) => id <= 0 || id > 0xffffffff) ||
        sequenceIds.length > 64) {
      throw const FormatException('Invalid or duplicate pattern region IDs.');
    }
    return AudioSessionDocument(
        title: title,
        tracks: tracks,
        instrumentTracks: instrumentTracks,
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

List<SavedAudioRegion> _regionsFromJson(Object? value, String trackId) {
  if (value is! List ||
      value.isEmpty ||
      value.length > AudioSessionDocument.maxTracks) {
    throw const FormatException('Invalid audio region list or region limit.');
  }
  return value
      .map((region) => SavedAudioRegion.fromJson(region, trackId))
      .toList(growable: false);
}

List<SavedSequenceRegion> _sequenceRegionsFromJson(Object? value) {
  if (value is! List || value.length > 64) {
    throw const FormatException('Invalid pattern region list.');
  }
  return value.map((entry) {
    if (entry is! Map<String, dynamic>) {
      throw const FormatException('Pattern region must be an object.');
    }
    final id = entry['id'];
    final start = entry['startSeconds'];
    final notes = entry['notes'];
    if (id is! int ||
        id <= 0 ||
        id > 0xffffffff ||
        start is! num ||
        !start.isFinite ||
        start < 0 ||
        start > 86400 ||
        notes is! List ||
        notes.length != 16 ||
        notes.any((note) =>
            note != null && (note is! int || note < 0 || note > 127))) {
      throw const FormatException('Invalid pattern region data.');
    }
    return SavedSequenceRegion(
      id: id,
      startSeconds: start.toDouble(),
      notes: List<int?>.unmodifiable(notes.cast<int?>()),
    );
  }).toList(growable: false);
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
