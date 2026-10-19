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

  AudioSessionDocument document(
          {double gain = 0.4, bool muted = false, bool solo = false}) =>
      AudioSessionDocument(title: 'Indie sketches', tracks: [
        SavedAudioTrack(
            id: 'native-stable-001',
            name: 'Guitar / verse',
            sourceUri: audio.absolute.uri.toString(),
            gain: gain,
            pan: 0.75,
            muted: muted,
            solo: solo),
      ]);

  test('saved session round-trips track identities and mixer parameters',
      () async {
    final path = '${directory.path}/sketch.aetherband.json';
    await store.save(path, document(solo: true));
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
    expect(reopened.performance.preset, 0);
    expect(reopened.performance.tempo, 92);
    expect(
        File(path).readAsString(), completion(contains('"schemaVersion": 2')));
  });

  test('session restores instrument macros tempo click and original phrase',
      () async {
    final settings = const PerformanceSettings().copyWith(
        preset: 1,
        macros: const [0.7, 0.6, 0.2, 0.3, 0.8],
        tempo: 137,
        metronome: true,
        sequence: true,
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
    expect(restored.performance.master, 0.55);
  });

  test('version one sessions retain compatible default instrument settings',
      () {
    final old = document().toJson()
      ..['schemaVersion'] = 1
      ..remove('performance');
    expect(AudioSessionDocument.fromJson(old).performance.preset, 0);
    expect(
        () => AudioSessionDocument.fromJson({
              ...document().toJson(),
              'performance': {'preset': 99}
            }),
        throwsFormatException);
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
