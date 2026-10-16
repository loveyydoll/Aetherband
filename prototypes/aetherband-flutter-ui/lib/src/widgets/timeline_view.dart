import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'clip_tile.dart';

class TimelineView extends StatelessWidget {
  const TimelineView({
    required this.tracks,
    required this.selectedTrackId,
    required this.selectedClipId,
    required this.zoom,
    required this.playheadSeconds,
    required this.tempo,
    required this.onTrackSelected,
    required this.onClipSelected,
    required this.onClipMoved,
    required this.onMuteChanged,
    required this.onSoloChanged,
    required this.onVolumeChanged,
    super.key,
  });

  final List<TrackModel> tracks;
  final String selectedTrackId;
  final String? selectedClipId;
  final double zoom;
  final double playheadSeconds;
  final int tempo;
  final ValueChanged<TrackModel> onTrackSelected;
  final void Function(TrackModel, ClipModel) onClipSelected;
  final void Function(TrackModel, ClipModel, double) onClipMoved;
  final void Function(TrackModel, bool) onMuteChanged;
  final void Function(TrackModel, bool) onSoloChanged;
  final void Function(TrackModel, double) onVolumeChanged;

  static const double _headerWidth = 210;
  static const double _rulerHeight = 38;
  static const double _laneHeight = 70;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseWidth = math.max(1400.0, constraints.maxWidth / zoom).toDouble();
        final contentWidth = baseWidth * zoom;
        final playheadX =
            (playheadSeconds * tempo / 240 * 84 * zoom).clamp(0.0, contentWidth).toDouble();

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _headerWidth,
              child: Column(
                children: [
                  Container(
                    height: _rulerHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.centerLeft,
                    decoration: const BoxDecoration(
                      color: AetherColors.panel,
                      border: Border(
                        bottom: BorderSide(color: AetherColors.raised),
                        right: BorderSide(color: AetherColors.raised),
                      ),
                    ),
                    child: const Text(
                      'TRACKS / 06',
                      style: TextStyle(
                        color: AetherColors.secondaryText,
                        fontSize: 10,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final track in tracks)
                    _TrackHeader(
                      key: ValueKey(track.id),
                      track: track,
                      selected: track.id == selectedTrackId,
                      onTap: () => onTrackSelected(track),
                      onMute: () => onMuteChanged(track, !track.muted),
                      onSolo: () => onSoloChanged(track, !track.solo),
                      onVolumeChanged: (value) => onVolumeChanged(track, value),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentWidth,
                    height: _rulerHeight + tracks.length * _laneHeight,
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            _TimelineRuler(width: contentWidth, zoom: zoom),
                            for (final track in tracks)
                              _TimelineLane(
                                key: ValueKey('lane-${track.id}'),
                                track: track,
                                width: contentWidth,
                                zoom: zoom,
                                selectedClipId: selectedClipId,
                                onClipSelected: (clip) => onClipSelected(track, clip),
                                onClipMoved: (clip, dx) => onClipMoved(track, clip, dx),
                              ),
                          ],
                        ),
                        Positioned(
                          left: playheadX,
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(width: 1.5, color: AetherColors.magenta),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrackHeader extends StatelessWidget {
  const _TrackHeader({
    required this.track,
    required this.selected,
    required this.onTap,
    required this.onMute,
    required this.onSolo,
    required this.onVolumeChanged,
    super.key,
  });

  final TrackModel track;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onMute;
  final VoidCallback onSolo;
  final ValueChanged<double> onVolumeChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AetherColors.raised : AetherColors.panel,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: _TimelineTrackConstants.laneHeight,
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 7),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: track.color.withValues(alpha: 0.8), width: 3),
              bottom: const BorderSide(color: AetherColors.raised, width: 0.7),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? AetherColors.paper : AetherColors.paper.withValues(alpha: 0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(track.kind, style: const TextStyle(color: AetherColors.secondaryText, fontSize: 8, letterSpacing: 0.6)),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  _MiniButton(label: 'M', active: track.muted, color: AetherColors.magenta, onTap: onMute),
                  const SizedBox(width: 4),
                  _MiniButton(label: 'S', active: track.solo, color: AetherColors.sage, onTap: onSolo),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: track.volume.clamp(0.0, 1.0).toDouble(),
                      onChanged: onVolumeChanged,
                      min: 0,
                      max: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class _TimelineTrackConstants {
  static const double laneHeight = 70;
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 21,
      child: Material(
        color: active ? color.withValues(alpha: 0.2) : AetherColors.background,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? color : AetherColors.secondaryText,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineRuler extends StatelessWidget {
  const _TimelineRuler({required this.width, required this.zoom});

  final double width;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final bars = (width / (84 * zoom)).ceil();
    return SizedBox(
      height: 38,
      width: width,
      child: Row(
        children: [
          for (var i = 0; i < bars; i++)
            Container(
              width: 84 * zoom,
              padding: const EdgeInsets.only(left: 6, top: 7),
              decoration: const BoxDecoration(
                color: AetherColors.panel,
                border: Border(
                  left: BorderSide(color: AetherColors.raised, width: 0.6),
                  bottom: BorderSide(color: AetherColors.raised),
                ),
              ),
              child: Text(
                "${(i + 1).toString().padLeft(2, '0')}",
                style: const TextStyle(color: AetherColors.secondaryText, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineLane extends StatelessWidget {
  const _TimelineLane({
    required this.track,
    required this.width,
    required this.zoom,
    required this.selectedClipId,
    required this.onClipSelected,
    required this.onClipMoved,
    super.key,
  });

  final TrackModel track;
  final double width;
  final double zoom;
  final String? selectedClipId;
  final ValueChanged<ClipModel> onClipSelected;
  final void Function(ClipModel, double) onClipMoved;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 70,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: TimelineGridPainter(zoom: zoom))),
          for (final clip in track.clips)
            Positioned(
              left: clip.start * zoom,
              top: 9,
              width: math.max(48.0, clip.width * zoom).toDouble(),
              height: 50,
              child: ClipTile(
                clip: clip,
                isSelected: clip.id == selectedClipId,
                onTap: () => onClipSelected(clip),
                onMove: (dx) => onClipMoved(clip, dx),
              ),
            ),
        ],
      ),
    );
  }
}

class TimelineGridPainter extends CustomPainter {
  const TimelineGridPainter({required this.zoom});

  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()..color = AetherColors.grid..strokeWidth = 0.6;
    final major = Paint()..color = AetherColors.raised..strokeWidth = 1.0;
    var index = 0;
    for (var x = 0.0; x <= size.width; x += 21 * zoom) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), index % 4 == 0 ? major : minor);
      index++;
    }
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), major);
  }

  @override
  bool shouldRepaint(covariant TimelineGridPainter oldDelegate) => oldDelegate.zoom != zoom;
}
