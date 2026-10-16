import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherband_flutter_ui/src/aetherband_app.dart';

void main() {
  testWidgets('renders the Aetherband demo workspace and toggles transport', (tester) async {
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

    expect(find.byTooltip('Pause transport'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'The transport interaction should not throw.');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
