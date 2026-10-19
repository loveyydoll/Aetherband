import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherband_desktop/src/aetherband_app.dart';
import 'audio_import_test.dart' show FakeEngine;

void main() {
  testWidgets('renders the Aetherband workspace without Flutter exceptions',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester
        .pumpWidget(AetherbandApp(createEngine: () async => FakeEngine()));
    await tester.pumpAndSettle();

    expect(find.text('Aetherband'), findsOneWidget);
    expect(find.text('HYPNOSYNTH'), findsOneWidget);
    expect(find.text('Morning Haze'), findsWidgets);
    expect(find.text('DEMO CONTENT · NO AUDIO FILES'), findsNothing);
    expect(find.text('lead vocal / close'), findsNothing);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Untitled Session'), findsOneWidget);
    expect(find.byTooltip('Play transport'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'The initial workspace should fit without overflow.');

    await tester.tap(find.byTooltip('Recording unavailable'));
    await tester.pump();
    expect(find.textContaining('Audio recording is not implemented yet'),
        findsOneWidget);
    expect(tester.takeException(), isNull,
        reason:
            'Unavailable recording must not fake a successful state change.');

    // Native loading has a separate integration test; widget tests do not open
    // real hardware or depend on a machine-specific native library.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Record menu metronome configures the audio transport',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = FakeEngine();

    await tester.pumpWidget(AetherbandApp(createEngine: () async => engine));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Record menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toggle Metronome'));
    await tester.pumpAndSettle();

    expect(engine.calls, contains('transport:92.0:true:false'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
