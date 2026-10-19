import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherband_desktop/src/models.dart';
import 'package:aetherband_desktop/src/theme.dart';
import 'package:aetherband_desktop/src/widgets/clip_tile.dart';

void main() {
  testWidgets('renders decoded audio peaks instead of a generated waveform',
      (tester) async {
    final clip = ClipModel(
      id: 'recorded-clip',
      title: 'recorded.wav',
      start: 0,
      width: 160,
      color: AetherColors.sage,
      isDemo: false,
      durationSeconds: 1,
      waveformPeaks: const [0.1, 0.8, 0.3, 0.6],
      waveformLoaded: true,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 180,
          height: 60,
          child: ClipTile(
            clip: clip,
            isSelected: false,
            onTap: () {},
            onMove: (_) {},
            onMoveStart: () {},
            onMoveEnd: () {},
          ),
        ),
      ),
    ));

    expect(find.byKey(const ValueKey('audio-waveform-recorded-clip')),
        findsOneWidget);
    expect(find.text('Waveform unavailable'), findsNothing);
    await tester.ensureVisible(find.byType(ClipTile));
    await tester.tap(find.byType(ClipTile));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message,
        contains('Decoded PCM waveform'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not call a waveform unsupported while it is loading',
      (tester) async {
    final clip = ClipModel(
      id: 'loading-clip',
      title: 'audio.wav',
      start: 0,
      width: 160,
      color: AetherColors.sage,
      isDemo: false,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 180,
          height: 60,
          child: ClipTile(
            clip: clip,
            isSelected: false,
            onTap: () {},
            onMove: (_) {},
            onMoveStart: () {},
            onMoveEnd: () {},
          ),
        ),
      ),
    ));

    expect(find.text('Analyzing waveform…'), findsOneWidget);
    expect(find.text('Waveform unavailable'), findsNothing);
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message,
        contains('Analyzing waveform'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('labels unsupported waveforms after analysis completes',
      (tester) async {
    final clip = ClipModel(
      id: 'unsupported-clip',
      title: 'audio.mp3',
      start: 0,
      width: 160,
      color: AetherColors.sage,
      isDemo: false,
      waveformLoaded: true,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 180,
          height: 60,
          child: ClipTile(
            clip: clip,
            isSelected: false,
            onTap: () {},
            onMove: (_) {},
            onMoveStart: () {},
            onMoveEnd: () {},
          ),
        ),
      ),
    ));

    expect(find.text('Waveform unavailable'), findsOneWidget);
    expect(find.text('Analyzing waveform…'), findsNothing);
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message,
        contains('Waveform unavailable'));
    expect(tester.takeException(), isNull);
  });
}
