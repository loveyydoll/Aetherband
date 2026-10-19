import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aetherband_desktop/src/session_store.dart';
import 'package:aetherband_desktop/src/performance_settings.dart';

void main() {
  late Directory directory;
  late File audio;
  late AudioSessionStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aetherband-session-');
    audio = File('${directory.path}/guitar take.wav');
    await audio.writeAsBytes([82, 73, 70, 70]);
    store = const AudioSessionStore();
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  AudioSessionDocument document({
    double gain = 0.4,
    bool muted = false,
    bool solo = false,
    double startSeconds = 0,
  }) =>
      AudioSessionDocument(title: 'Indie sketches', tracks: [
        SavedAudioTrack(
            id: 'native-stable-001',
            name: 'Guitar / verse',
            sourceUri: audio.absolute.uri.toString(),
            gain: gain,
            pan: 0.75,
            muted: muted,
            solo: solo,
            startSeconds: startSeconds),
      ]);

  test('saved session round-trips track identities and mixer parameters',
      () async {
    final path = '${directory.path}/sketch.aetherband.json';
    await store.save(path, document(solo: true, startSeconds: 2.75));
    final reopened = await store.open(path);
    expect(reopened.title, 'Indie sketches');
    expect(reopened.tracks.single.id, 'native-stable-001');
    expect(reopened.tracks.single.name, 'Guitar / verse');
    expect(File(reopened.tracks.single.sourcePath).absolute.uri,
        audio.absolute.uri);
    expect(reopened.tracks.single.gain, 0.4);
    expect(reopened.tracks.single.pan, 0.75);
    expect(reopened.tracks.single.muted, false);
    expect(reopened.tracks.single.solo, true);
    expect(reopened.tracks.single.startSeconds, 2.75);
    expect(reopened.performance.preset, 0);
    expect(reopened.performance.tempo, 92);
    expect(
        File(path).readAsString(), completion(contains('"schemaVersion": 5')));
  });

  test('split regions round-trip source ranges and timeline positions', () {
    final split = document().tracks.single;
    final encoded = AudioSessionDocument(
      title: 'Split take',
      tracks: [
        SavedAudioTrack(
          id: split.id,
          name: split.name,
          sourceUri: split.sourceUri,
          gain: split.gain,
          pan: split.pan,
          muted: split.muted,
          regions: const [
            SavedAudioRegion(
              id: 'native-stable-001-clip',
              startSeconds: 0,
              sourceStartSeconds: 0,
              durationSeconds: 2.5,
            ),
            SavedAudioRegion(
              id: 'native-stable-001-region-right',
              startSeconds: 2.5,
              sourceStartSeconds: 2.5,
              durationSeconds: 1.75,
            ),
          ],
        ),
      ],
    ).toJson();

    final restored = AudioSessionDocument.fromJson(encoded);
    expect(restored.tracks.single.effectiveRegions, hasLength(2));
    expect(restored.tracks.single.effectiveRegions[1].startSeconds, 2.5);
    expect(restored.tracks.single.effectiveRegions[1].sourceStartSeconds, 2.5);
    expect(restored.tracks.single.effectiveRegions[1].durationSeconds, 1.75);
  });

  test('schema four split regions still migrate without instrument tracks', () {
    final split = document().tracks.single;
    final schemaFour = AudioSessionDocument(
      title: 'Legacy split',
      tracks: [
        SavedAudioTrack(
          id: split.id,
          name: split.name,
          sourceUri: split.sourceUri,
          gain: split.gain,
          pan: split.pan,
          muted: split.muted,
          regions: const [
            SavedAudioRegion(
              id: 'native-stable-001-clip',
              startSeconds: 0,
              durationSeconds: 2.5,
            ),
            SavedAudioRegion(
              id: 'native-stable-001-region-right',
              startSeconds: 2.5,
              sourceStartSeconds: 2.5,
              durationSeconds: 1.75,
            ),
          ],
        ),
      ],
    ).toJson()
      ..['schemaVersion'] = 4
      ..remove('instrumentTracks');
    final restored = AudioSessionDocument.fromJson(schemaFour);
    expect(restored.tracks.single.effectiveRegions, hasLength(2));
    expect(restored.instrumentTracks, isEmpty);
  });

  test('session restores instrument macros tempo click and editable sequence',
      () async {
    final settings = const PerformanceSettings().copyWith(
        preset: 1,
        macros: const [0.7, 0.6, 0.2, 0.3, 0.8],
        tempo: 137,
        metronome: true,
        sequence: true,
        sequenceNotes: const [
          60,
          null,
          64,
          67,
          ...<int?>[
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null
          ]
        ],
        master: 0.55);
    final path = '${directory.path}/instrument.aetherband.json';
    await store.save(
        path,
        AudioSessionDocument(
            title: 'Night', tracks: const [], performance: settings));
    final restored = await store.open(path);
    expect(restored.performance.preset, 1);
    expect(restored.performance.macros, settings.macros);
    expect(restored.performance.tempo, 137);
    expect(restored.performance.metronome, isTrue);
    expect(restored.performance.sequence, isTrue);
    expect(restored.performance.sequenceNotes, settings.sequenceNotes);
    expect(restored.performance.master, 0.55);
  });

  test('HypnoSynth track identity round-trips in schema five', () {
    final encoded = AudioSessionDocument(
      title: 'Synth sketch',
      tracks: const [],
      instrumentTracks: const [
        SavedInstrumentTrack(
          id: 'hypno-1',
          name: 'HypnoSynth',
          gain: 0.35,
          pan: 0.8,
          muted: true,
          solo: true,
        ),
      ],
    ).toJson();
    final restored = AudioSessionDocument.fromJson(encoded);
    expect(restored.instrumentTracks.single.id, 'hypno-1');
    expect(restored.instrumentTracks.single.name, 'HypnoSynth');
    expect(restored.instrumentTracks.single.gain, 0.35);
    expect(restored.instrumentTracks.single.pan, 0.8);
    expect(restored.instrumentTracks.single.muted, isTrue);
    expect(restored.instrumentTracks.single.solo, isTrue);
  });

  test('older performance settings default to the original 16-step phrase', () {
    final old = const PerformanceSettings().toJson()..remove('sequenceNotes');
    expect(
        PerformanceSettings.fromJson(old).sequenceNotes, defaultHypnoSequence);
    expect(
      () => PerformanceSettings.fromJson({
        ...old,
        'sequenceNotes': [60, null],
      }),
      throwsFormatException,
    );
  });

  test('version one sessions retain compatible default instrument settings',
      () {
    final old = document().toJson()
      ..['schemaVersion'] = 1
      ..remove('performance');
    ((old['tracks'] as List).single as Map<String, Object?>)
        .remove('startSeconds');
    expect(AudioSessionDocument.fromJson(old).performance.preset, 0);
    expect(
        () => AudioSessionDocument.fromJson({
              ...document().toJson(),
              'performance': {'preset': 99}
            }),
        throwsFormatException);
  });

  test('version two audio sessions remain readable with clips at zero', () {
    final old = document().toJson()..['schemaVersion'] = 2;
    final tracks = old['tracks'] as List<Map<String, Object?>>;
    tracks.single.remove('startSeconds');
    final opened = AudioSessionDocument.fromJson(old);
    expect(opened.tracks.single.startSeconds, 0);
  });

  test('overwriting a session preserves the newest document', () async {
    final path = '${directory.path}/overwritten.aetherband.json';
    await store.save(path, document());
    await store.save(path, document(gain: 0.8, muted: true));
    final reopened = await store.open(path);
    expect(reopened.tracks.single.gain, 0.8);
    expect(reopened.tracks.single.muted, isTrue);
    expect(await File('$path.bak').exists(), isFalse);
  });

  test('interrupted replacement can recover the original backup', () async {
    final path = '${directory.path}/recovered.aetherband.json';
    await store.save(path, document());
    await File(path).rename('$path.bak');
    final reopened = await store.open(path);
    expect(reopened.tracks.single.name, 'Guitar / verse');
  });

  test('a missing referenced audio file cannot silently open', () async {
    final path = '${directory.path}/missing.aetherband.json';
    await store.save(path, document());
    await audio.delete();
    await expectLater(store.open(path), throwsA(isA<FileSystemException>()));
  });

  test('invalid, unknown-version and duplicate-id projects are rejected', () {
    final good = document().toJson();
    expect(() => AudioSessionDocument.fromJson({...good, 'schemaVersion': 99}),
        throwsFormatException);
    final track = (good['tracks'] as List).single;
    expect(
        () => AudioSessionDocument.fromJson({
              ...good,
              'tracks': [track, track]
            }),
        throwsFormatException);
    expect(
        () => SavedAudioTrack.fromJson({
              ...(track as Map<String, Object?>),
              'gain': double.nan,
            }),
        throwsFormatException);
    expect(
      () => SavedInstrumentTrack.fromJson({
        'id': 'hypno-1',
        'name': 'HypnoSynth',
        'gain': 1.1,
      }),
      throwsFormatException,
    );
    expect(
        () => SavedAudioTrack.fromJson({
              ...track,
              'startSeconds': -1,
            }),
        throwsFormatException);
    expect(
        () => SavedAudioTrack.fromJson({
              ...track,
              'sourceUri': 'https://example.com/song.wav',
            }),
        throwsFormatException);
  });

  test('malformed JSON never mutates a saved session', () async {
    final path = '${directory.path}/corrupt.aetherband.json';
    await File(path).writeAsString('{ broken json');
    await expectLater(store.open(path), throwsA(isA<FormatException>()));
    expect(await File(path).readAsString(), '{ broken json');
  });

  test('session files with excessive size are rejected', () async {
    final path = '${directory.path}/huge.aetherband.json';
    await File(path).writeAsString(' ' * (2 * 1024 * 1024 + 1));
    await expectLater(store.open(path), throwsA(isA<FormatException>()));
  });

  test('serialized schema is ordinary UTF-8 JSON', () {
    final encoded = jsonEncode(document().toJson());
    final decoded = AudioSessionDocument.fromJson(jsonDecode(encoded));
    expect(decoded.tracks.length, 1);
    expect(decoded.tracks.single.sourceUri, audio.absolute.uri.toString());
  });
}
