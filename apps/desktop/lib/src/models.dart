import 'package:flutter/material.dart';

import 'theme.dart';

double timelinePixelsPerSecond(int tempo) => tempo / 240 * 84;

class ClipModel {
  ClipModel({
    required this.id,
    required this.title,
    required this.start,
    required this.width,
    required this.color,
    this.isDemo = true,
    this.durationSeconds,
  });

  final String id;
  final String title;
  double start;
  final double width;
  final Color color;
  final bool isDemo;
  final double? durationSeconds;

  double timelineWidth(int tempo) => isDemo
      ? width
      : durationSeconds == null
          ? 140 // Explicitly labelled unknown; not presented as a measured length.
          : durationSeconds! * timelinePixelsPerSecond(tempo);
}

class TrackModel {
  TrackModel({
    required this.id,
    required this.name,
    required this.kind,
    required this.color,
    required this.clips,
    this.muted = false,
    this.solo = false,
    this.volume = 0.78,
    this.pan = 0,
  });

  final String id;
  final String name;
  final String kind;
  final Color color;
  final List<ClipModel> clips;
  bool muted;
  bool solo;
  double volume;
  double pan;
}

List<TrackModel> createDemoTracks() => [
  TrackModel(id: 'vocal', name: 'lead vocal / close', kind: 'AUDIO', color: AetherColors.sage, clips: [
    ClipModel(id: 'v1', title: 'verse — take 04', start: 28, width: 222, color: AetherColors.sage),
    ClipModel(id: 'v2', title: 'double / breath', start: 285, width: 151, color: AetherColors.sage),
    ClipModel(id: 'v3', title: 'chorus layers', start: 620, width: 248, color: AetherColors.sage),
  ]),
  TrackModel(id: 'guitar', name: 'detuned guitar', kind: 'AUDIO', color: const Color(0xFFB4A0CE), clips: [
    ClipModel(id: 'g1', title: 'amp room', start: 40, width: 332, color: const Color(0xFFB4A0CE)),
    ClipModel(id: 'g2', title: 'reverse swell', start: 485, width: 150, color: const Color(0xFFB4A0CE)),
    ClipModel(id: 'g3', title: 'wide take', start: 646, width: 214, color: const Color(0xFFB4A0CE)),
  ]),
  TrackModel(id: 'afterimage', name: 'afterimage pad', kind: 'INSTRUMENT', color: AetherColors.magenta, clips: [
    ClipModel(id: 's1', title: 'soft focus', start: 180, width: 290, color: AetherColors.magenta),
    ClipModel(id: 's2', title: 'slow bloom', start: 520, width: 348, color: AetherColors.magenta),
  ]),
  TrackModel(id: 'sample', name: 'sample / memory', kind: 'SAMPLE', color: const Color(0xFFD7A56D), clips: [
    ClipModel(id: 'p1', title: 'room tone 07', start: 20, width: 130, color: const Color(0xFFD7A56D)),
    ClipModel(id: 'p2', title: 'cut-up phrase', start: 360, width: 162, color: const Color(0xFFD7A56D)),
    ClipModel(id: 'p3', title: 'tape fragment', start: 704, width: 126, color: const Color(0xFFD7A56D)),
  ]),
  TrackModel(id: 'bass', name: 'soft bass', kind: 'AUDIO', color: const Color(0xFF83B6C1), clips: [
    ClipModel(id: 'b1', title: 'sub / warm', start: 30, width: 335, color: const Color(0xFF83B6C1)),
    ClipModel(id: 'b2', title: 'chorus return', start: 610, width: 255, color: const Color(0xFF83B6C1)),
  ]),
  TrackModel(id: 'automation', name: 'space / send', kind: 'AUTOMATION', color: AetherColors.blue, clips: [
    ClipModel(id: 'a1', title: 'send bloom', start: 210, width: 285, color: AetherColors.blue),
    ClipModel(id: 'a2', title: 'tail / dissolve', start: 610, width: 280, color: AetherColors.blue),
  ]),
];