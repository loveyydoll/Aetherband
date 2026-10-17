import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherband_desktop/src/aetherband_app.dart';

void main() {
  testWidgets('renders the Aetherband workspace and reports unavailable native engine', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AetherbandApp());

    expect(find.text('Aetherband'), findsOneWidget);
    expect(find.text('AFTERIMAGE'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Untitled Session'), findsOneWidget);
    expect(find.byTooltip('Play transport'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'The initial workspace should fit without overflow.');

    await tester.tap(find.byTooltip('Play transport'));
    await tester.pump();
    // Allow the asynchronous native-library initialization to fail and rebuild
    // the workspace without pumpAndSettle, which can hang on ongoing animations.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Native engine unavailable:'), findsOneWidget);
    expect(find.byTooltip('Play transport'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'A missing native library must be reported rather than simulated.');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
