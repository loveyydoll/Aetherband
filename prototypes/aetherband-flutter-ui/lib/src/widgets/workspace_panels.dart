import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

class BrowserPanel extends StatelessWidget {
  const BrowserPanel({
    required this.category,
    required this.onCategoryChanged,
    required this.onPresetSelected,
    super.key,
  });

  final String category;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onPresetSelected;

  static const categories = ['Instruments', 'Presets', 'Effects', 'Samples', 'Projects'];
  static const items = <String, List<String>>{
    'Instruments': ['Afterimage', 'Soft Focus', 'Glass Choir', 'Room Tone'],
    'Presets': ['Warm Haze', 'Pale Blue', 'Slow Bloom', 'Velvet Tape'],
    'Effects': ['Afterglow Reverb', 'Memory Chorus', 'Soft Saturation', 'Reverse Room'],
    'Samples': ['Field recordings', 'Drum fragments', 'Vocal textures', 'Found sounds'],
    'Projects': ['Recent sessions', 'Artist templates', 'Sketches', 'Finished mixes'],
  };

  @override
  Widget build(BuildContext context) {
    final currentItems = items[category] ?? const <String>[];
    return Container(
      decoration: const BoxDecoration(
        color: AetherColors.background,
        border: Border(right: BorderSide(color: AetherColors.raised)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 15, 12, 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_outlined, color: AetherColors.sage, size: 15),
                SizedBox(width: 8),
                Text('LIBRARY', style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Find a sound...',
                hintStyle: const TextStyle(color: AetherColors.secondaryText, fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 16),
                isDense: true,
                filled: true,
                fillColor: AetherColors.panel,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
          for (final item in categories)
            InkWell(
              onTap: () => onCategoryChanged(item),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                color: item == category ? AetherColors.raised : Colors.transparent,
                child: Row(
                  children: [
                    Icon(_categoryIcon(item), size: 15, color: item == category ? AetherColors.sage : AetherColors.secondaryText),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(item, style: TextStyle(
                        fontSize: 12,
                        color: item == category ? AetherColors.paper : AetherColors.secondaryText,
                        fontWeight: item == category ? FontWeight.w600 : FontWeight.normal,
                      )),
                    ),
                    if (item == category)
                      Container(
                        width: 3,
                        height: 20,
                        decoration: BoxDecoration(color: AetherColors.magenta, borderRadius: BorderRadius.circular(4)),
                      ),
                  ],
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(15, 20, 15, 7),
            child: Text('COLLECTION', style: TextStyle(color: AetherColors.secondaryText, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 15),
            child: Text('Soft-focus studies', style: TextStyle(color: AetherColors.paper, fontSize: 12)),
          ),
          const SizedBox(height: 3),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 15),
            child: Text('12 presets · original sounds', style: TextStyle(color: AetherColors.secondaryText, fontSize: 10)),
          ),
          const Divider(height: 25, indent: 14, endIndent: 14),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final item in currentItems)
                  ListTile(
                    dense: true,
                    visualDensity: const VisualDensity(vertical: -3),
                    leading: Icon(_itemIcon(category), size: 16, color: AetherColors.sage),
                    title: Text(item, style: const TextStyle(fontSize: 11)),
                    onTap: () => onPresetSelected(item),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('DEMO CONTENT · NO AUDIO FILES', style: TextStyle(color: AetherColors.secondaryText, fontSize: 8, letterSpacing: 0.4)),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String item) => switch (item) {
    'Instruments' => Icons.music_note_outlined,
    'Presets' => Icons.tune,
    'Effects' => Icons.blur_on,
    'Samples' => Icons.graphic_eq,
    _ => Icons.folder_open_outlined,
  };

  IconData _itemIcon(String item) => switch (item) {
    'Instruments' => Icons.piano_outlined,
    'Presets' => Icons.waves,
    'Effects' => Icons.auto_fix_high,
    'Samples' => Icons.audio_file,
    _ => Icons.folder_outlined,
  };
}

class InstrumentDock extends StatelessWidget {
  const InstrumentDock({
    required this.isMixer,
    required this.onTabChanged,
    required this.preset,
    required this.onPresetChanged,
    required this.knobValues,
    required this.onKnobChanged,
    required this.tracks,
    required this.onVolumeChanged,
    required this.peakLeft,
    required this.peakRight,
    super.key,
  });

  final bool isMixer;
  final ValueChanged<bool> onTabChanged;
  final String preset;
  final ValueChanged<String?> onPresetChanged;
  final Map<String, double> knobValues;
  final void Function(String, double) onKnobChanged;
  final List<TrackModel> tracks;
  final void Function(TrackModel, double) onVolumeChanged;
  final double peakLeft;
  final double peakRight;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 202,
      decoration: const BoxDecoration(
        color: AetherColors.panel,
        border: Border(top: BorderSide(color: AetherColors.raised)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 37,
            child: Row(
              children: [
                _DockTab(label: 'DEVICE', selected: !isMixer, onTap: () => onTabChanged(false)),
                _DockTab(label: 'MIXER', selected: isMixer, onTap: () => onTabChanged(true)),
                const Spacer(),
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AetherColors.background, borderRadius: BorderRadius.circular(4)),
                  child: const Text('MOCK ENGINE / NO AUDIO', style: TextStyle(color: AetherColors.secondaryText, fontSize: 8, letterSpacing: 0.6)),
                ),
              ],
            ),
          ),
          Expanded(child: isMixer ? _buildMixer() : _buildDevice()),
        ],
      ),
    );
  }

  Widget _buildDevice() {
    return Row(
      children: [
        SizedBox(
          width: 205,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('EFFECT CHAIN', style: TextStyle(color: AetherColors.secondaryText, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const _EffectTile(name: 'Memory Chorus', detail: 'soft modulation', color: AetherColors.blue),
                const SizedBox(height: 5),
                const _EffectTile(name: 'Afterglow Reverb', detail: 'wide / slow', color: AetherColors.sage),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1, color: AetherColors.raised),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 9, 18, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('AFTERIMAGE', style: TextStyle(color: AetherColors.paper, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
                    const SizedBox(width: 12),
                    const Text('TEXTURE SYNTH / DEMO', style: TextStyle(color: AetherColors.secondaryText, fontSize: 9, letterSpacing: 0.7)),
                    const Spacer(),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: preset,
                        dropdownColor: AetherColors.raised,
                        style: const TextStyle(color: AetherColors.paper, fontSize: 11),
                        items: const [
                          DropdownMenuItem(value: 'Soft Focus', child: Text('Soft Focus')),
                          DropdownMenuItem(value: 'Pale Blue', child: Text('Pale Blue')),
                          DropdownMenuItem(value: 'Slow Bloom', child: Text('Slow Bloom')),
                          DropdownMenuItem(value: 'Velvet Tape', child: Text('Velvet Tape')),
                        ],
                        onChanged: onPresetChanged,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Wrap(
                  alignment: WrapAlignment.start,
                  spacing: 24,
                  runSpacing: 4,
                  children: [
                    for (final item in const [
                      ('Tone', AetherColors.sage),
                      ('Motion', AetherColors.blue),
                      ('Space', AetherColors.magenta),
                      ('Drift', AetherColors.sage),
                      ('Mix', AetherColors.paper),
                    ])
                      DialControl(
                        label: item.$1,
                        accent: item.$2,
                        value: knobValues[item.$1] ?? 0.5,
                        onChanged: (value) => onKnobChanged(item.$1, value),
                      ),
                  ],
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1, color: AetherColors.raised),
        SizedBox(
          width: 138,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('OUTPUT', style: TextStyle(color: AetherColors.secondaryText, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _MeterBar(label: 'L', value: peakLeft, color: AetherColors.sage),
                const SizedBox(height: 8),
                _MeterBar(label: 'R', value: peakRight, color: AetherColors.magenta),
                const Spacer(),
                const Text('DEMO METER ONLY', style: TextStyle(color: AetherColors.secondaryText, fontSize: 8)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMixer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final track in tracks)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                decoration: BoxDecoration(
                  color: AetherColors.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border(top: BorderSide(color: track.color, width: 2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AetherColors.paper)),
                    const Spacer(),
                    Text('${(track.volume * 100).round()}%', style: const TextStyle(fontSize: 10, color: AetherColors.secondaryText)),
                    Slider(value: track.volume.clamp(0.0, 1.0).toDouble(), onChanged: (value) => onVolumeChanged(track, value), min: 0, max: 1),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DockTab extends StatelessWidget {
  const _DockTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 37,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: selected ? AetherColors.magenta : Colors.transparent, width: 2)),
        ),
        child: Center(
          child: Text(label, style: TextStyle(
            color: selected ? AetherColors.paper : AetherColors.secondaryText,
            fontSize: 10,
            letterSpacing: 1,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          )),
        ),
      ),
    );
  }
}

class _EffectTile extends StatelessWidget {
  const _EffectTile({required this.name, required this.detail, required this.color});

  final String name;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AetherColors.background,
        borderRadius: BorderRadius.circular(5),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name, style: const TextStyle(color: AetherColors.paper, fontSize: 10, fontWeight: FontWeight.w600)),
                Text(detail, style: const TextStyle(color: AetherColors.secondaryText, fontSize: 9)),
              ],
            ),
          ),
          Icon(Icons.more_horiz, color: AetherColors.secondaryText.withOpacity(0.75), size: 16),
        ],
      ),
    );
  }
}

class DialControl extends StatelessWidget {
  const DialControl({
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
    super.key,
  });

  final String label;
  final double value;
  final Color accent;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onVerticalDragUpdate: (details) => onChanged((value - details.delta.dy / 130).clamp(0.0, 1.0).toDouble()),
            onDoubleTap: () => onChanged(0.5),
            child: CustomPaint(
              size: const Size(44, 44),
              painter: DialPainter(value: value, accent: accent),
              child: const SizedBox(width: 44, height: 44),
            ),
          ),
          const SizedBox(height: 2),
          Text(label.toUpperCase(), style: const TextStyle(color: AetherColors.secondaryText, fontSize: 8, letterSpacing: 0.5)),
          Text('${(value * 100).round()}', style: const TextStyle(color: AetherColors.paper, fontSize: 9)),
        ],
      ),
    );
  }
}

class DialPainter extends CustomPainter {
  const DialPainter({required this.value, required this.accent});

  final double value;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: 17);
    final track = Paint()..color = AetherColors.raised..style = PaintingStyle.stroke..strokeWidth = 3.5..strokeCap = StrokeCap.round;
    final progress = Paint()..color = accent..style = PaintingStyle.stroke..strokeWidth = 3.5..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi * 0.75, math.pi * 1.5, false, track);
    canvas.drawArc(rect, math.pi * 0.75, math.pi * 1.5 * value, false, progress);
    canvas.drawCircle(center, 12.5, Paint()..color = AetherColors.background);
    final angle = math.pi * 0.75 + math.pi * 1.5 * value;
    canvas.drawLine(
      center,
      Offset(center.dx + math.cos(angle) * 9, center.dy + math.sin(angle) * 9),
      Paint()..color = AetherColors.paper..strokeWidth = 2..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant DialPainter oldDelegate) => oldDelegate.value != value || oldDelegate.accent != accent;
}

class _MeterBar extends StatelessWidget {
  const _MeterBar({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 12, child: Text(label, style: const TextStyle(color: AetherColors.secondaryText, fontSize: 10))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 7,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: AetherColors.raised),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value.clamp(0.0, 1.0).toDouble(),
                    child: ColoredBox(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
