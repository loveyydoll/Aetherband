import 'dart:async';

import 'package:flutter/material.dart';

import 'mock_engine.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets/timeline_view.dart';
import 'widgets/workspace_panels.dart';

class AetherbandApp extends StatelessWidget {
  const AetherbandApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aetherband',
      debugShowCheckedModeBanner: false,
      theme: AetherTheme.dark,
      home: const AetherbandWorkspace(),
    );
  }
}

class AetherbandWorkspace extends StatefulWidget {
  const AetherbandWorkspace({super.key});

  @override
  State<AetherbandWorkspace> createState() => _AetherbandWorkspaceState();
}

class _AetherbandWorkspaceState extends State<AetherbandWorkspace> {
  final EngineController _engine = MockEngineController();
  final List<TrackModel> _tracks = createDemoTracks();
  final Map<String, double> _knobValues = {
    'Tone': 0.62,
    'Motion': 0.44,
    'Space': 0.75,
    'Drift': 0.31,
    'Mix': 0.58,
  };

  StreamSubscription<EngineTelemetry>? _telemetrySubscription;
  EngineTelemetry _telemetry = const EngineTelemetry(
    playheadSeconds: 0,
    peakLeft: 0,
    peakRight: 0,
    isPlaying: false,
  );

  String _selectedTrackId = 'afterimage';
  String? _selectedClipId;
  String _browserCategory = 'Instruments';
  String _preset = 'Soft Focus';
  bool _browserOpen = true;
  bool _isRecording = false;
  bool _showMixer = false;
  double _zoom = 1;

  TrackModel get _selectedTrack => _tracks.firstWhere((track) => track.id == _selectedTrackId);

  @override
  void initState() {
    super.initState();
    _telemetrySubscription = _engine.telemetry.listen((value) {
      if (mounted) setState(() => _telemetry = value);
    });
  }

  @override
  void dispose() {
    _telemetrySubscription?.cancel();
    unawaited(_engine.dispose());
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_telemetry.isPlaying) {
      await _engine.stop();
    } else {
      await _engine.play();
    }
  }

  Future<void> _stop() async {
    await _engine.stop();
  }

  void _moveClip(TrackModel track, ClipModel clip, double deltaPx) {
    setState(() {
      clip.start = (clip.start + deltaPx / _zoom).clamp(0.0, 2200.0).toDouble();
      _selectedTrackId = track.id;
      _selectedClipId = clip.id;
    });
  }

  void _selectClip(TrackModel track, ClipModel clip) {
    setState(() {
      _selectedTrackId = track.id;
      _selectedClipId = clip.id;
    });
  }

  void _selectTrack(TrackModel track) {
    setState(() {
      _selectedTrackId = track.id;
      _selectedClipId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 1000;
            return Column(
              children: [
                _TopBar(
                  isPlaying: _telemetry.isPlaying,
                  isRecording: _isRecording,
                  browserOpen: _browserOpen,
                  onPlay: _togglePlay,
                  onStop: _stop,
                  onRecord: () => setState(() => _isRecording = !_isRecording),
                  onBrowser: () => setState(() => _browserOpen = !_browserOpen),
                ),
                Expanded(
                  child: Row(
                    children: [
                      if (_browserOpen && !compact)
                        SizedBox(
                          width: 222,
                          child: BrowserPanel(
                            category: _browserCategory,
                            onCategoryChanged: (category) => setState(() => _browserCategory = category),
                            onPresetSelected: (name) {
                              setState(() {
                                _preset = const ['Soft Focus', 'Pale Blue', 'Slow Bloom', 'Velvet Tape'].contains(name)
                                    ? name
                                    : 'Soft Focus';
                                _selectedTrackId = 'afterimage';
                              });
                            },
                          ),
                        ),
                      Expanded(
                        child: Column(
                          children: [
                            _TimelineToolbar(
                              selectedTrack: _selectedTrack.name,
                              zoom: _zoom,
                              onZoomChanged: (value) => setState(() => _zoom = value),
                              browserOpen: _browserOpen,
                              onBrowser: () => setState(() => _browserOpen = !_browserOpen),
                            ),
                            Expanded(
                              child: TimelineView(
                                tracks: _tracks,
                                selectedTrackId: _selectedTrackId,
                                selectedClipId: _selectedClipId,
                                zoom: _zoom,
                                playheadSeconds: _telemetry.playheadSeconds,
                                tempo: 92,
                                onTrackSelected: _selectTrack,
                                onClipSelected: _selectClip,
                                onClipMoved: _moveClip,
                                onMuteChanged: (track, value) => setState(() => track.muted = value),
                                onSoloChanged: (track, value) => setState(() => track.solo = value),
                                onVolumeChanged: (track, value) => setState(() => track.volume = value),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                InstrumentDock(
                  isMixer: _showMixer,
                  onTabChanged: (value) => setState(() => _showMixer = value),
                  preset: const ['Soft Focus', 'Pale Blue', 'Slow Bloom', 'Velvet Tape'].contains(_preset)
                      ? _preset
                      : 'Soft Focus',
                  onPresetChanged: (value) {
                    if (value != null) setState(() => _preset = value);
                  },
                  knobValues: _knobValues,
                  onKnobChanged: (name, value) => setState(() => _knobValues[name] = value),
                  tracks: _tracks,
                  onVolumeChanged: (track, value) => setState(() => track.volume = value),
                  peakLeft: _telemetry.peakLeft,
                  peakRight: _telemetry.peakRight,
                ),
                const _StatusBar(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isPlaying,
    required this.isRecording,
    required this.browserOpen,
    required this.onPlay,
    required this.onStop,
    required this.onRecord,
    required this.onBrowser,
  });

  final bool isPlaying;
  final bool isRecording;
  final bool browserOpen;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onRecord;
  final VoidCallback onBrowser;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AetherColors.background,
        border: Border(bottom: BorderSide(color: AetherColors.raised)),
      ),
      child: Row(
        children: [
          Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              color: AetherColors.sage.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AetherColors.sage.withOpacity(0.5)),
            ),
            child: const Icon(Icons.graphic_eq, color: AetherColors.sage, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('aetherband', style: TextStyle(color: AetherColors.paper, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
              Text('UNTITLED PROJECT / EARLY ALPHA', style: TextStyle(color: AetherColors.secondaryText.withOpacity(0.85), fontSize: 8, letterSpacing: 1.0)),
            ],
          ),
          const SizedBox(width: 20),
          Container(width: 1, height: 29, color: AetherColors.raised),
          const SizedBox(width: 14),
          _TransportButton(icon: Icons.stop_rounded, tooltip: 'Stop demo transport', onTap: onStop),
          const SizedBox(width: 4),
          _TransportButton(
            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: isPlaying ? 'Pause demo transport' : 'Play demo transport',
            onTap: onPlay,
            primary: true,
          ),
          const SizedBox(width: 4),
          _TransportButton(
            icon: Icons.fiber_manual_record,
            tooltip: 'Toggle simulated recording state',
            onTap: onRecord,
            color: isRecording ? AetherColors.magenta : AetherColors.secondaryText,
          ),
          const SizedBox(width: 13),
          Container(
            width: 92,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: AetherColors.panel, borderRadius: BorderRadius.circular(6)),
            child: const Column(
              children: [
                Text('TEMPO', style: TextStyle(color: AetherColors.secondaryText, fontSize: 8, letterSpacing: 1)),
                SizedBox(height: 2),
                Text('92.0 BPM', style: TextStyle(color: AetherColors.paper, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 67,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            decoration: BoxDecoration(color: AetherColors.panel, borderRadius: BorderRadius.circular(6)),
            child: const Column(
              children: [
                Text('METER', style: TextStyle(color: AetherColors.secondaryText, fontSize: 8, letterSpacing: 1)),
                SizedBox(height: 4),
                Text('4 / 4', style: TextStyle(color: AetherColors.paper, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: AetherColors.magenta.withOpacity(0.1),
              border: Border.all(color: AetherColors.magenta.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Row(
              children: [
                Icon(Icons.science_outlined, color: AetherColors.magenta, size: 13),
                SizedBox(width: 6),
                Text('DEMO ONLY · NO AUDIO', style: TextStyle(color: AetherColors.paper, fontSize: 9, letterSpacing: 0.4)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: browserOpen ? 'Close browser' : 'Open browser',
            onPressed: onBrowser,
            icon: Icon(Icons.view_sidebar_outlined, color: browserOpen ? AetherColors.sage : AetherColors.secondaryText),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.settings_outlined, size: 19, color: AetherColors.secondaryText),
        ],
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.primary = false,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool primary;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Material(
          color: primary ? AetherColors.sage.withOpacity(0.15) : AetherColors.panel,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: onTap,
            child: Icon(icon, size: 19, color: color ?? (primary ? AetherColors.sage : AetherColors.paper)),
          ),
        ),
      ),
    );
  }
}

class _TimelineToolbar extends StatelessWidget {
  const _TimelineToolbar({
    required this.selectedTrack,
    required this.zoom,
    required this.onZoomChanged,
    required this.browserOpen,
    required this.onBrowser,
  });

  final String selectedTrack;
  final double zoom;
  final ValueChanged<double> onZoomChanged;
  final bool browserOpen;
  final VoidCallback onBrowser;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: const BoxDecoration(
        color: AetherColors.panel,
        border: Border(bottom: BorderSide(color: AetherColors.raised)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: browserOpen ? 'Hide browser' : 'Show browser',
            onPressed: onBrowser,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.view_sidebar_outlined, size: 17),
          ),
          const SizedBox(width: 6),
          const Text('ARRANGEMENT', style: TextStyle(color: AetherColors.paper, fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          Container(width: 1, height: 20, color: AetherColors.raised),
          const SizedBox(width: 12),
          const Icon(Icons.layers_outlined, size: 15, color: AetherColors.sage),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Selected: $selectedTrack', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AetherColors.secondaryText, fontSize: 11)),
          ),
          const Icon(Icons.zoom_out, size: 15, color: AetherColors.secondaryText),
          SizedBox(width: 120, child: Slider(value: zoom, min: 0.65, max: 1.5, onChanged: onZoomChanged)),
          const Icon(Icons.zoom_in, size: 15, color: AetherColors.secondaryText),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(color: AetherColors.background, borderRadius: BorderRadius.circular(4)),
            child: Text('${(zoom * 100).round()}%', style: const TextStyle(color: AetherColors.secondaryText, fontSize: 10)),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: AetherColors.background,
      child: const Row(
        children: [
          Icon(Icons.circle, color: AetherColors.sage, size: 6),
          SizedBox(width: 6),
          Text('UI PROTOTYPE', style: TextStyle(color: AetherColors.secondaryText, fontSize: 8, letterSpacing: 0.6)),
          Spacer(),
          Text('ENGINE DISCONNECTED · TRANSPORT IS SIMULATED', style: TextStyle(color: AetherColors.secondaryText, fontSize: 8, letterSpacing: 0.4)),
          SizedBox(width: 8),
          Text('WINDOWS / macOS', style: TextStyle(color: AetherColors.sage, fontSize: 8, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}
