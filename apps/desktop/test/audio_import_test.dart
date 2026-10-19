import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherband_desktop/src/aetherband_app.dart';
import 'package:aetherband_desktop/src/engine_controller.dart';
import 'package:aetherband_desktop/src/models.dart';
import 'package:aetherband_desktop/src/widgets/clip_tile.dart';
import 'package:aetherband_desktop/src/widgets/workspace_panels.dart';
import 'package:aetherband_desktop/src/widgets/timeline_view.dart';
import 'package:aetherband_desktop/src/session_store.dart';

class FakeEngine implements EngineController, PerformanceEngine {
  final frames = StreamController<EngineTelemetry>.broadcast();
  final calls = <String>[];
  Completer<LoadedAudioTrack>? importResult;
  Completer<void>? removalResult;
  Object? importError;
  Object? mixerError;
  int disposeCount = 0;
  int count = 0;

  @override
  Stream<EngineTelemetry> get telemetry => frames.stream;
  @override
  Future<void> play() async {
    calls.add('play');
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<LoadedAudioTrack> loadTrack(String path) async {
    calls.add('load:$path');
    if (importError != null) throw importError!;
    final loaded = await (importResult?.future ??
        Future.value(
          LoadedAudioTrack(
              id: ++count,
              totalFrames: 44100 * 120,
              sampleRateHz: 44100,
              channels: 2),
        ));
    return loaded;
  }

  @override
  Future<void> removeTrack(int trackId) async {
    calls.add('remove:$trackId');
    await removalResult?.future;
  }

  @override
  Future<void> setTrackVolume(int trackId, double gain) async {
    calls.add('volume:$trackId:$gain');
    if (mixerError != null) throw mixerError!;
  }

  @override
  Future<void> setTrackPan(int trackId, double pan) async {
    calls.add('pan:$trackId:$pan');
  }

  @override
  Future<void> setTrackStartSeconds(int trackId, double seconds) async {
    calls.add('start:$trackId:$seconds');
  }

  @override
  Future<void> muteTrack(int trackId, bool muted) async {
    calls.add('mute:$trackId:$muted');
  }

  @override
  Future<void> soloTrack(int trackId, bool solo) async {
    calls.add('solo:$trackId:$solo');
  }

  @override
  Future<void> synthEvent(int event, int key, double value) async {
    calls.add('synth:$event:$key:$value');
  }

  @override
  Future<void> configureTransport(
      double bpm, bool metronome, bool sequence) async {
    calls.add('transport:$bpm:$metronome:$sequence');
  }

  @override
  Future<void> setMasterVolume(double gain) async {
    calls.add('master:$gain');
  }

  @override
  Future<int> getTrackCount() async => count;
  @override
  Future<void> dispose() async {
    disposeCount++;
    await frames.close();
  }
}

Finder get importedClip => find
    .byWidgetPredicate((widget) => widget is ClipTile && !widget.clip.isDemo);

Future<void> mountWorkspace(
  WidgetTester tester,
  FakeEngine engine, {
  Future<XFile?> Function()? picker,
  Future<EngineController> Function()? factory,
  Future<XFile?> Function()? sessionPicker,
  Future<String?> Function()? sessionSavePicker,
  double width = 1440,
  double height = 1000,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(AetherbandApp(
    createEngine: factory ?? () async => engine,
    pickAudioFile: picker ?? () async => XFile('C:/audio/take.wav'),
    pickSessionFile: sessionPicker,
    pickSessionSavePath: sessionSavePicker,
  ));
  await tester.pumpAndSettle();
}

Future<void> importAudio(WidgetTester tester) async {
  await tester.tap(find.text('Import audio'));
  await tester.pumpAndSettle();
}

Future<void> deleteSelected(WidgetTester tester, {bool settle = true}) async {
  await tester.tap(find.text('Track'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete Selected Track'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  test('source rate determines duration; absent frame counts stay unknown', () {
    expect(
        const LoadedAudioTrack(
                id: 1, totalFrames: 44100, sampleRateHz: 44100, channels: 1)
            .durationSeconds,
        1);
    expect(
        const LoadedAudioTrack(
                id: 2, totalFrames: 0, sampleRateHz: 48000, channels: 2)
            .durationSeconds,
        isNull);
    expect(
        const LoadedAudioTrack(
                id: 3, totalFrames: 48000, sampleRateHz: 0, channels: 2)
            .durationSeconds,
        isNull);
  });

  testWidgets(
      'import uses real duration, extends timeline and has no invented waveform',
      (tester) async {
    final engine = FakeEngine();
    await mountWorkspace(tester, engine);
    await importAudio(tester);
    expect(engine.calls, ['stop', 'load:C:/audio/take.wav']);
    expect(importedClip, findsOneWidget);
    expect(tester.getSize(importedClip).width,
        closeTo(120 * timelinePixelsPerSecond(92), 0.01));
    expect(find.text('120.00 s'), findsOneWidget);
    expect(find.textContaining('1 AUDIO TRACK'), findsOneWidget);
    expect(
        find.descendant(
            of: importedClip,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is CustomPaint && widget.painter is WaveformPainter,
            )),
        findsNothing);
    await tester.ensureVisible(importedClip);
    final clip = tester.widget<ClipTile>(importedClip).clip;
    await tester.dragFrom(
        tester.getTopLeft(importedClip) + const Offset(20, 20),
        const Offset(150, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(clip.startSeconds, greaterThan(0));
    final beatSeconds = 60 / 92;
    expect(
      clip.startSeconds,
      closeTo((clip.startSeconds / beatSeconds).round() * beatSeconds, 1e-9),
    );
    expect(engine.calls.last, startsWith('start:1:'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(engine.disposeCount, 1);
  });

  testWidgets('picker cancellation leaves transport and inventory untouched',
      (tester) async {
    final engine = FakeEngine();
    await mountWorkspace(tester, engine, picker: () async => null);
    await importAudio(tester);
    expect(engine.calls, isEmpty);
    expect(importedClip, findsNothing);
    expect(find.text('Import audio'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed import reports error and keeps the engine available',
      (tester) async {
    final engine = FakeEngine()..importError = StateError('Unsupported file');
    await mountWorkspace(tester, engine);
    await importAudio(tester);
    expect(importedClip, findsNothing);
    expect(find.textContaining('Audio import failed:'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.text('Import audio'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'unknown metadata is labelled and imports fit a constrained window',
      (tester) async {
    final engine = FakeEngine()..importResult = Completer<LoadedAudioTrack>();
    await mountWorkspace(tester, engine, width: 900, height: 800);
    await tester.tap(find.text('Import audio'));
    await tester.pump();
    expect(find.text('Importing…'), findsOneWidget);
    await tester.tap(find.byTooltip('Play transport'));
    await tester.pump();
    expect(engine.calls, ['stop', 'load:C:/audio/take.wav']);
    engine.importResult!.complete(const LoadedAudioTrack(
        id: 1, totalFrames: 0, sampleRateHz: 44100, channels: 2));
    await tester.pumpAndSettle();
    expect(find.text('Duration unknown'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'removal targets the requested track when selection changes in flight',
      (tester) async {
    final engine = FakeEngine();
    var pick = 0;
    await mountWorkspace(
      tester,
      engine,
      picker: () async => XFile(
        pick++ == 0 ? 'C:/audio/removed.wav' : 'C:/audio/target.wav',
      ),
    );
    await importAudio(tester);
    await importAudio(tester);
    final beforeRemoval = tester
        .widget<TimelineView>(find.byType(TimelineView));
    expect(beforeRemoval.tracks, hasLength(2));
    engine.removalResult = Completer<void>();
    await deleteSelected(tester, settle: false);
    final timeline = tester.widget<TimelineView>(find.byType(TimelineView));
    timeline.onTrackSelected(beforeRemoval.tracks.first);
    await tester.pump();
    engine.removalResult!.complete();
    await tester.pumpAndSettle();
    expect(engine.calls.last, 'remove:2');
    final afterRemoval = tester.widget<TimelineView>(find.byType(TimelineView));
    expect(afterRemoval.tracks, hasLength(1));
    expect(afterRemoval.tracks.single.id, beforeRemoval.tracks.first.id);
    expect(afterRemoval.selectedTrackId, beforeRemoval.tracks.first.id);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed removal retains clip and supports retry', (tester) async {
    final engine = FakeEngine();
    await mountWorkspace(tester, engine);
    await importAudio(tester);
    engine.removalResult = Completer<void>();
    await deleteSelected(tester, settle: false);
    engine.removalResult!.completeError(StateError('Command queue full'));
    await tester.pumpAndSettle();
    expect(importedClip, findsOneWidget);
    expect(find.textContaining('Track removal failed:'), findsOneWidget);
    engine.removalResult = null;
    await deleteSelected(tester);
    expect(importedClip, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('closing workspace during import never updates disposed widgets',
      (tester) async {
    final engine = FakeEngine()..importResult = Completer<LoadedAudioTrack>();
    await mountWorkspace(tester, engine);
    await tester.tap(find.text('Import audio'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    engine.importResult!.complete(const LoadedAudioTrack(
        id: 1, totalFrames: 44100, sampleRateHz: 44100, channels: 2));
    await tester.pumpAndSettle();
    expect(engine.disposeCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'engine retry clears old native IDs and disposes the previous owner',
      (tester) async {
    final first = FakeEngine();
    final replacement = FakeEngine();
    var creations = 0;
    final restarted = Completer<void>();
    await mountWorkspace(tester, first, factory: () async {
      if (creations++ == 0) return first;
      restarted.complete();
      return replacement;
    });
    await importAudio(tester);
    first.frames.addError(StateError('Device disconnected'));
    await tester.pumpAndSettle();
    expect(creations, 1);
    final retryButton = tester.widget<TextButton>(find.ancestor(
        of: find.text('Retry'), matching: find.byType(TextButton)));
    expect(retryButton.onPressed, isNotNull);
    await tester.tap(find.text('Retry'));
    // Stream cancellation can complete outside the widget fake clock; allow
    // that event turn, then pump the replacement's UI updates.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(first.disposeCount, 1);
    expect(restarted.isCompleted, isTrue);
    expect(importedClip, findsNothing);
    expect(find.textContaining('DEMO CLIPS ONLY'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(replacement.disposeCount, 1);
  });
  testWidgets('imported audio mixer uses native volume, pan and mute',
      (tester) async {
    final engine = FakeEngine();
    await mountWorkspace(tester, engine);
    await importAudio(tester);
    final dock = tester.widget<InstrumentDock>(find.byType(InstrumentDock));
    final importedTrack =
        dock.tracks.singleWhere((track) => track.id.startsWith('native-'));
    expect(importedTrack.pan, 0.5);
    dock.onVolumeChanged(importedTrack, 0.25);
    dock.onPanChanged(importedTrack, 0.75);
    dock.onMuteChanged(importedTrack, true);
    await tester.pumpAndSettle();
    expect(
        engine.calls,
        containsAllInOrder([
          'volume:1:0.25',
          'pan:1:0.75',
          'mute:1:true',
        ]));
    expect(importedTrack.volume, 0.25);
    expect(importedTrack.pan, 0.75);
    expect(importedTrack.muted, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rejected native fader operation restores previous UI value',
      (tester) async {
    final engine = FakeEngine()..mixerError = StateError('command queue full');
    await mountWorkspace(tester, engine);
    await importAudio(tester);
    final dock = tester.widget<InstrumentDock>(find.byType(InstrumentDock));
    final importedTrack =
        dock.tracks.singleWhere((track) => track.id.startsWith('native-'));
    expect(importedTrack.volume, 0.8);
    dock.onVolumeChanged(importedTrack, 0.3);
    await tester.pumpAndSettle();
    expect(engine.calls, contains('volume:1:0.3'));
    expect(importedTrack.volume, 0.8);
    expect(find.textContaining('Track volume failed:'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('session file menu saves and restores real native mixer state',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('aetherband-ui-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final audio = File('${directory.path}/voice.wav');
    audio.writeAsBytesSync([82, 73, 70, 70]);
    final sessionPath = '${directory.path}/sketch.aetherband.json';
    final first = FakeEngine();
    final restored = FakeEngine();
    var creations = 0;
    final stagedEngine = Completer<void>();

    await mountWorkspace(
      tester,
      first,
      picker: () async => XFile(audio.path),
      sessionPicker: () async => XFile(sessionPath),
      sessionSavePicker: () async => sessionPath,
      factory: () async {
        if (creations++ == 0) return first;
        stagedEngine.complete();
        return restored;
      },
    );
    await importAudio(tester);
    final imported = tester
        .widget<InstrumentDock>(find.byType(InstrumentDock))
        .tracks
        .singleWhere((track) => track.id.startsWith('native-'));
    final stableId = imported.id;
    final mixer = tester.widget<InstrumentDock>(find.byType(InstrumentDock));
    mixer.onVolumeChanged(imported, 0.35);
    mixer.onPanChanged(imported, 0.8);
    mixer.onMuteChanged(imported, true);
    mixer.onSoloChanged(imported, true);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('File menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Session'));
    await tester.pump();
    await tester.runAsync(() async {
      final project = File(sessionPath);
      for (var i = 0; i < 100 && !await project.exists(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(project.existsSync(), isTrue);
    });
    await tester.pumpAndSettle();
    final saved = (await tester.runAsync(
      () => const AudioSessionStore().open(sessionPath),
    ))!;
    expect(saved.tracks.single.id, stableId);
    expect(saved.tracks.single.gain, 0.35);
    expect(saved.tracks.single.pan, 0.8);
    expect(saved.tracks.single.muted, isTrue);
    expect(saved.tracks.single.solo, isTrue);

    // The save runs asynchronously from the menu callback. Wait for the UI
    // completion signal before issuing another session command.
    await tester.pumpAndSettle();
    expect(find.textContaining('Saved 1 real audio tracks.'), findsOneWidget);
    await tester.tap(find.byTooltip('File menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Session…'));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && !stagedEngine.isCompleted; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(stagedEngine.isCompleted, isTrue);
      for (var i = 0; i < 100 && first.disposeCount == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(first.disposeCount, 1);
    });
    await tester.pumpAndSettle();
    expect(
        restored.calls,
        containsAllInOrder([
          'load:${File.fromUri(audio.absolute.uri).path}',
          'volume:1:0.35',
          'pan:1:0.8',
          'mute:1:true',
          'solo:1:true',
          'start:1:0.0',
        ]));
    final reopened = tester
        .widget<InstrumentDock>(find.byType(InstrumentDock))
        .tracks
        .singleWhere((track) => track.id == stableId);
    expect(reopened.volume, 0.35);
    expect(reopened.pan, 0.8);
    expect(reopened.muted, isTrue);
    expect(reopened.solo, isTrue);
    expect(first.disposeCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Ctrl+S shortcut saves imported audio without using the menu',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('aetherband-keys-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final audio = File('${directory.path}/track.wav');
    audio.writeAsBytesSync([82, 73, 70, 70]);
    final project = File('${directory.path}/keyboard.aetherband.json');
    final engine = FakeEngine();
    await mountWorkspace(
      tester,
      engine,
      picker: () async => XFile(audio.path),
      sessionSavePicker: () async => project.path,
    );
    await importAudio(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && !await project.exists(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    expect(project.existsSync(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
