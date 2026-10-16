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

    expect(find.text('aetherband'), findsOneWidget);
    expect(find.text('AFTERIMAGE'), findsOneWidget);
    expect(find.text('DEMO ONLY · NO AUDIO'), findsOneWidget);
    expect(find.byTooltip('Play demo transport'), findsOneWidget);

    await tester.tap(find.byTooltip('Play demo transport'));
    await tester.pump();

    expect(find.byTooltip('Pause demo transport'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
