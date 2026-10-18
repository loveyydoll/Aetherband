import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherband_desktop/src/aetherband_app.dart';
import 'package:aetherband_desktop/src/engine_controller.dart';
import 'package:aetherband_desktop/src/models.dart';
import 'package:aetherband_desktop/src/widgets/clip_tile.dart';

class FakeEngine implements EngineController {
  final frames = StreamController<EngineTelemetry>.broadcast();
  final calls = <String>[];
  Completer<LoadedAudioTrack>? importResult;
  Completer<void>? removalResult;
  Object? importError;
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
    await tester.pump();
    expect(clip.start, 0,
        reason: 'A visual drag must not claim to move native audio.');
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
    await mountWorkspace(tester, engine);
    await importAudio(tester);
    engine.removalResult = Completer<void>();
    await deleteSelected(tester, settle: false);
    await tester.ensureVisible(find.text('lead vocal / close'));
    await tester.tap(find.text('lead vocal / close'));
    await tester.pump();
    engine.removalResult!.complete();
    await tester.pumpAndSettle();
    expect(engine.calls.last, 'remove:1');
    expect(importedClip, findsNothing);
    expect(find.text('lead vocal / close'), findsOneWidget);
    expect(find.text('Selected: lead vocal / close'), findsOneWidget);
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
}
