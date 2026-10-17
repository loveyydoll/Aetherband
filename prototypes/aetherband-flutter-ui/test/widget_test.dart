import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherband_desktop/src/aetherband_app.dart';

void main() {
  testWidgets('renders the Aetherband workspace without Flutter exceptions', (tester) async {
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

    await tester.tap(find.byTooltip('Recording unavailable'));
    await tester.pump();
    expect(find.textContaining('Audio recording is not implemented yet'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'Unavailable recording must not fake a successful state change.');

    // Native engine availability depends on the test machine's built artifacts.
    // This widget test checks the workspace itself, not a machine-specific
    // assumption that the native library must be absent.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
