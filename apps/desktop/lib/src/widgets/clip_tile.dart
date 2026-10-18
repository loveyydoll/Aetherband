import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

class ClipTile extends StatelessWidget {
  const ClipTile({
    required this.clip,
    required this.isSelected,
    required this.onTap,
    required this.onMove,
    super.key,
  });

  final ClipModel clip;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<double> onMove;

  @override
  Widget build(BuildContext context) {
    final base = clip.color;
    final duration = clip.durationSeconds;
    return Tooltip(
      message: clip.isDemo
          ? 'Demo clip'
          : '${clip.title} · ${duration == null ? 'Duration unknown' : '${duration.toStringAsFixed(2)} s'} · Waveform not generated',
      child: GestureDetector(
        onTap: onTap,
        onHorizontalDragUpdate:
            clip.isDemo ? (details) => onMove(details.delta.dx) : null,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: base.withValues(alpha: isSelected ? 0.28 : 0.15),
            border: Border.all(
              color: isSelected
                  ? AetherColors.paper
                  : base.withValues(alpha: 0.65),
              width: isSelected ? 1.4 : 0.8,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (clip.isDemo)
                Positioned.fill(
                  child: CustomPaint(
                    painter: WaveformPainter(
                        color: base.withValues(alpha: 0.86),
                        seed: clip.id.hashCode),
                  ),
                ),
              if (!clip.isDemo)
                Positioned(
                  left: 8,
                  right: 6,
                  bottom: 5,
                  child: Text(
                    duration == null
                        ? 'Duration unknown'
                        : '${duration.toStringAsFixed(2)} s',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                        color: AetherColors.secondaryText, fontSize: 9),
                  ),
                ),
              Positioned(
                left: 8,
                right: 6,
                top: 5,
                child: Text(
                  clip.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AetherColors.paper,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    shadows: [
                      Shadow(color: AetherColors.background, blurRadius: 3)
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  const WaveformPainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final centerY = size.height * 0.66;
    final count = (size.width / 5).floor().clamp(1, 250);
    for (var i = 0; i < count; i++) {
      final x = i * 5.0 + 3;
      final n =
          (math.sin((i + seed % 31) * 0.71) * math.cos((i + seed % 19) * 0.19))
              .abs();
      final envelope =
          0.25 + 0.75 * math.sin(math.pi * (i + 1) / (count + 1)).abs();
      final amplitude = 3 + n * envelope * (size.height * 0.31);
      canvas.drawLine(Offset(x, centerY - amplitude),
          Offset(x, centerY + amplitude), paint);
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
}
