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
    required this.onMoveStart,
    required this.onMoveEnd,
    super.key,
  });

  final ClipModel clip;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<double> onMove;
  final VoidCallback onMoveStart;
  final VoidCallback onMoveEnd;

  @override
  Widget build(BuildContext context) {
    final base = clip.color;
    final duration = clip.durationSeconds;
    final peaks = clip.waveformPeaks;
    final waveformStatus = !clip.waveformLoaded
        ? 'Analyzing waveform'
        : peaks == null
            ? 'Waveform unavailable for this audio format'
            : 'Decoded PCM waveform';
    return Tooltip(
      message: clip.isDemo
          ? 'Demo clip'
          : '${clip.title} · ${duration == null ? 'Duration unknown' : '${duration.toStringAsFixed(2)} s'} · $waveformStatus',
      child: GestureDetector(
        onTap: onTap,
        onHorizontalDragStart: (_) => onMoveStart(),
        onHorizontalDragUpdate: (details) => onMove(details.delta.dx),
        onHorizontalDragEnd: (_) => onMoveEnd(),
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
              if (!clip.isDemo && peaks != null)
                Positioned.fill(
                  child: CustomPaint(
                    key: ValueKey('audio-waveform-${clip.id}'),
                    painter: AudioWaveformPainter(
                      color: base.withValues(alpha: 0.88),
                      peaks: peaks,
                    ),
                  ),
                ),
              if (!clip.isDemo && !clip.waveformLoaded)
                const Positioned(
                  left: 8,
                  right: 6,
                  top: 24,
                  child: Text(
                    'Analyzing waveform…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AetherColors.secondaryText, fontSize: 8),
                  ),
                ),
              if (!clip.isDemo && clip.waveformLoaded && peaks == null)
                const Positioned(
                  left: 8,
                  right: 6,
                  top: 24,
                  child: Text(
                    'Waveform unavailable',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AetherColors.secondaryText, fontSize: 8),
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

class AudioWaveformPainter extends CustomPainter {
  const AudioWaveformPainter({required this.color, required this.peaks});

  final Color color;
  final List<double> peaks;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty || size.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final centerY = size.height * 0.62;
    final scaleY = size.height * 0.30;
    final scaleX = size.width / peaks.length;
    for (var i = 0; i < peaks.length; i++) {
      final amplitude = peaks[i].clamp(0.025, 1.0) * scaleY;
      final x = (i + 0.5) * scaleX;
      canvas.drawLine(Offset(x, centerY - amplitude),
          Offset(x, centerY + amplitude), paint);
    }
  }

  @override
  bool shouldRepaint(covariant AudioWaveformPainter oldDelegate) =>
      oldDelegate.color != color || !identical(oldDelegate.peaks, peaks);
}
