import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import 'engine_controller.dart';
import 'native_engine.dart';
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
  EngineController? _engine;
  Object? _engineError;
  final List<TrackModel> _tracks = createDemoTracks();
  final Map<String, int> _nativeTrackIds = <String, int>{};
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
    sampleRateHz: 0,
    peakLeft: 0,
    peakRight: 0,
    isPlaying: false,
  );

  String _selectedTrackId = 'afterimage';
  String? _selectedClipId;
  String _browserCategory = 'Instruments';
  String _preset = 'Soft Focus';
  bool _browserOpen = true;
  bool _showMixer = false;
  bool _initializingEngine = false;
  double _zoom = 1;

  TrackModel get _selectedTrack => _tracks.firstWhere((track) => track.id == _selectedTrackId);

  @override
  void initState() {
    super.initState();
    unawaited(_initializeEngine());
  }

  Future<void> _initializeEngine() async {
    if (_initializingEngine) return;
    _initializingEngine = true;

    try {
      // Retry must not orphan an existing native handle or leave its telemetry
      // timer/subscription alive if the error came from polling after startup.
      final previousEngine = _engine;
      _engine = null;
      await _telemetrySubscription?.cancel();
      _telemetrySubscription = null;
      if (previousEngine != null) await previousEngine.dispose();

      final engine = await NativeEngineController.create();
      if (!mounted) {
        await engine.dispose();
        return;
      }
      _engine = engine;
      _telemetrySubscription = engine.telemetry.listen(
        (value) { if (mounted) setState(() => _telemetry = value); },
        onError: (Object error) { if (mounted) setState(() => _engineError = error); },
      );
      setState(() => _engineError = null);
    } catch (error) {
      if (mounted) setState(() => _engineError = error);
    } finally {
      _initializingEngine = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _telemetrySubscription?.cancel();
    final engine = _engine;
    if (engine != null) unawaited(engine.dispose());
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final engine = _engine;
    if (engine == null) { _showEngineUnavailable(); return; }
    try {
      if (_telemetry.isPlaying) { await engine.pause(); } else { await engine.play(); }
    } catch (error) {
      if (mounted) setState(() => _engineError = error);
    }
  }

  Future<void> _stop() async {
    final engine = _engine;
    if (engine == null) { _showEngineUnavailable(); return; }
    try {
      await engine.stop();
    } catch (error) {
      if (mounted) setState(() => _engineError = error);
    }
  }

  void _showEngineUnavailable() {
    final message = _engineError?.toString() ?? 'Native audio engine is not ready.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showFeatureUnavailable(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is not implemented yet; no recording or project changes were made.'),
        duration: const Duration(seconds: 3),
      ),
    );
  }


  Future<void> _importAudio() async {
    final engine = _engine;
    if (engine == null) {
      _showEngineUnavailable();
      return;
    }
    const audioTypes = XTypeGroup(
      label: 'Audio',
      extensions: <String>['wav', 'aiff', 'aif', 'flac', 'mp3', 'ogg', 'm4a'],
    );
    try {
      final file = await openFile(acceptedTypeGroups: <XTypeGroup>[audioTypes]);
      if (file == null || !mounted) return;
      final nativeId = await engine.loadTrack(file.path);
      final name = file.name;
      final id = 'native-$nativeId';
      setState(() {
        _nativeTrackIds[id] = nativeId;
        _tracks.add(TrackModel(
          id: id,
          name: name,
          kind: 'AUDIO',
          color: AetherColors.sage,
          clips: <ClipModel>[
            ClipModel(
              id: '$id-clip',
              title: name,
              start: 0,
              width: 420,
              color: AetherColors.sage,
            ),
          ],
        ));
        _selectedTrackId = id;
        _selectedClipId = '$id-clip';
        _engineError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _engineError = error);
    }
  }

  Future<void> _removeSelectedTrack() async {
    final engine = _engine;
    final nativeId = _nativeTrackIds[_selectedTrackId];
    if (engine == null || nativeId == null) {
      _showFeatureUnavailable('Removing demo tracks');
      return;
    }
    try {
      await engine.removeTrack(nativeId);
      if (!mounted) return;
      setState(() {
        _tracks.removeWhere((track) => track.id == _selectedTrackId);
        _nativeTrackIds.remove(_selectedTrackId);
        _selectedTrackId = _tracks.first.id;
        _selectedClipId = null;
      });
    } catch (error) {
      if (mounted) setState(() => _engineError = error);
    }
  }

  void _handleMenuCommand(_MenuAction action) {
    switch (action.id) {
      case 'view.browser':
        setState(() => _browserOpen = !_browserOpen);
        return;
      case 'view.mixer':
        setState(() => _showMixer = !_showMixer);
        return;
      case 'track.addAudio':
        unawaited(_importAudio());
        return;
      case 'track.delete':
        unawaited(_removeSelectedTrack());
        return;
      case 'transport.play':
        unawaited(_togglePlay());
        return;
      case 'transport.stop':
        unawaited(_stop());
        return;
      case 'transport.record':
        _showFeatureUnavailable('Audio recording');
        return;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${action.label} is not connected in this UI prototype yet.'),
            duration: const Duration(seconds: 2),
          ),
        );
    }
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
                if (_engineError != null)
                  MaterialBanner(
                    content: Text('Native engine unavailable: $_engineError'),
                    actions: [TextButton(onPressed: () => unawaited(_initializeEngine()), child: const Text('Retry'))],
                  ),
                _MenuBar(onSelected: _handleMenuCommand),
                _TopBar(
                  isPlaying: _telemetry.isPlaying,
                  isRecording: false,
                  browserOpen: _browserOpen,
                  mixerOpen: _showMixer,
                  onPlay: _togglePlay,
                  onStop: _stop,
                  onRecord: () => _showFeatureUnavailable('Audio recording'),
                  onBrowser: () => setState(() => _browserOpen = !_browserOpen),
                  onMixer: () => setState(() => _showMixer = !_showMixer),
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
                _StatusBar(
                  engineConnected: _engine != null && _engineError == null,
                  isPlaying: _telemetry.isPlaying,
                  engineError: _engineError,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MenuAction {
  const _MenuAction(this.id, this.label, [this.shortcut]);

  final String id;
  final String label;
  final String? shortcut;
}

class _MenuBar extends StatelessWidget {
  const _MenuBar({required this.onSelected});

  final ValueChanged<_MenuAction> onSelected;

  static const Map<String, List<_MenuAction>> _menus = {
    'File': [
      _MenuAction('file.new', 'New Session', 'Ctrl+N'),
      _MenuAction('file.open', 'Open Session…', 'Ctrl+O'),
      _MenuAction('file.save', 'Save Session', 'Ctrl+S'),
      _MenuAction('file.saveAs', 'Save Session As…'),
      _MenuAction('file.export', 'Export Mixdown…', 'Ctrl+Alt+E'),
    ],
    'Edit': [
      _MenuAction('edit.undo', 'Undo', 'Ctrl+Z'),
      _MenuAction('edit.redo', 'Redo', 'Ctrl+Shift+Z'),
      _MenuAction('edit.cut', 'Cut', 'Ctrl+X'),
      _MenuAction('edit.copy', 'Copy', 'Ctrl+C'),
      _MenuAction('edit.paste', 'Paste', 'Ctrl+V'),
      _MenuAction('edit.duplicate', 'Duplicate', 'Ctrl+D'),
    ],
    'Track': [
      _MenuAction('track.addAudio', 'Add Audio Track'),
      _MenuAction('track.addInstrument', 'Add Instrument Track'),
      _MenuAction('track.addBus', 'Add Bus'),
      _MenuAction('track.duplicate', 'Duplicate Selected Track'),
      _MenuAction('track.delete', 'Delete Selected Track'),
    ],
    'Region': [
      _MenuAction('region.split', 'Split at Playhead'),
      _MenuAction('region.join', 'Join Selected Regions'),
      _MenuAction('region.bounce', 'Bounce in Place'),
    ],
    'Navigate': [
      _MenuAction('navigate.start', 'Go to Start', 'Home'),
      _MenuAction('navigate.previous', 'Previous Bar', '←'),
      _MenuAction('navigate.next', 'Next Bar', '→'),
      _MenuAction('navigate.end', 'Go to End', 'End'),
    ],
    'Record': [
      _MenuAction('transport.record', 'Toggle Recording', 'R'),
      _MenuAction('record.metronome', 'Toggle Metronome', 'K'),
      _MenuAction('record.countIn', 'Count-in Settings…'),
    ],
    'Mix': [
      _MenuAction('view.mixer', 'Show / Hide Mixer'),
      _MenuAction('mix.resetMeters', 'Reset Metering'),
      _MenuAction('mix.masterEffects', 'Master Effects'),
    ],
    'View': [
      _MenuAction('view.browser', 'Show / Hide Browser'),
      _MenuAction('view.mixer', 'Show / Hide Mixer'),
      _MenuAction('view.zoomToFit', 'Zoom to Fit'),
      _MenuAction('view.automation', 'Show Automation'),
    ],
    'Window': [
      _MenuAction('window.project', 'Project'),
      _MenuAction('window.plugins', 'Plug-in Windows'),
      _MenuAction('window.settings', 'Settings…'),
    ],
    'Help': [
      _MenuAction('help.shortcuts', 'Keyboard Shortcuts'),
      _MenuAction('help.docs', 'Documentation'),
      _MenuAction('help.about', 'About Aetherband'),
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 31,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AetherColors.background,
        border: Border(bottom: BorderSide(color: AetherColors.raised, width: 0.7)),
      ),
      child: Row(
        children: [
          Container(
            width: 21,
            height: 21,
            decoration: BoxDecoration(
              color: AetherColors.sage.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AetherColors.sage.withValues(alpha: 0.42)),
            ),
            child: const Icon(Icons.graphic_eq, color: AetherColors.sage, size: 14),
          ),
          const SizedBox(width: 7),
          const Text(
            'Aetherband',
            style: TextStyle(color: AetherColors.paper, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 13),
          Container(width: 1, height: 17, color: AetherColors.raised),
          const SizedBox(width: 4),
          for (final menu in _menus.entries)
            PopupMenuButton<_MenuAction>(
              tooltip: '${menu.key} menu',
              padding: EdgeInsets.zero,
              onSelected: onSelected,
              color: AetherColors.panel,
              surfaceTintColor: Colors.transparent,
              itemBuilder: (context) => menu.value.map((action) {
                return PopupMenuItem<_MenuAction>(
                  value: action,
                  height: 32,
                  child: SizedBox(
                    width: 205,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            action.label,
                            style: const TextStyle(color: AetherColors.paper, fontSize: 12),
                          ),
                        ),
                        if (action.shortcut != null)
                          Text(
                            action.shortcut!,
                            style: const TextStyle(color: AetherColors.secondaryText, fontSize: 10),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                child: Text(
                  menu.key,
                  style: const TextStyle(color: AetherColors.secondaryText, fontSize: 11),
                ),
              ),
            ),
          const Spacer(),
          const Icon(Icons.circle, size: 6, color: AetherColors.magenta),
          const SizedBox(width: 7),
          const Text('Untitled Session', style: TextStyle(color: AetherColors.paper, fontSize: 11)),
          const SizedBox(width: 11),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isPlaying,
    required this.isRecording,
    required this.browserOpen,
    required this.mixerOpen,
    required this.onPlay,
    required this.onStop,
    required this.onRecord,
    required this.onBrowser,
    required this.onMixer,
  });

  final bool isPlaying;
  final bool isRecording;
  final bool browserOpen;
  final bool mixerOpen;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onRecord;
  final VoidCallback onBrowser;
  final VoidCallback onMixer;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 49,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AetherColors.panel,
        border: Border(bottom: BorderSide(color: AetherColors.raised)),
      ),
      child: Row(
        children: [
          _TransportButton(icon: Icons.stop_rounded, tooltip: 'Stop transport', onTap: onStop),
          const SizedBox(width: 4),
          _TransportButton(
            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: isPlaying ? 'Pause transport' : 'Play transport',
            onTap: onPlay,
            primary: true,
          ),
          const SizedBox(width: 4),
          _TransportButton(
            icon: Icons.fiber_manual_record,
            tooltip: isRecording ? 'Stop recording' : 'Recording unavailable',
            onTap: onRecord,
            color: isRecording ? AetherColors.magenta : AetherColors.secondaryText,
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 25, color: AetherColors.raised),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AetherColors.background,
              border: Border.all(color: AetherColors.raised),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Row(
              children: [
                Icon(Icons.timeline, size: 14, color: AetherColors.sage),
                SizedBox(width: 7),
                Text('001 : 01 : 000', style: TextStyle(color: AetherColors.paper, fontSize: 11, fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const _ValuePlate(label: 'TEMPO', value: '92.0'),
          const SizedBox(width: 6),
          const _ValuePlate(label: 'METER', value: '4/4', width: 61),
          const Spacer(),
          Text(
            'UI PREVIEW',
            style: TextStyle(color: AetherColors.secondaryText.withValues(alpha: 0.78), fontSize: 9, letterSpacing: 0.8),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: browserOpen ? 'Hide browser' : 'Show browser',
            onPressed: onBrowser,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.view_sidebar_outlined, size: 18, color: browserOpen ? AetherColors.sage : AetherColors.secondaryText),
          ),
          IconButton(
            tooltip: mixerOpen ? 'Hide mixer' : 'Show mixer',
            onPressed: onMixer,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.equalizer, size: 18, color: mixerOpen ? AetherColors.magenta : AetherColors.secondaryText),
          ),
          const SizedBox(width: 3),
          const Icon(Icons.settings_outlined, size: 17, color: AetherColors.secondaryText),
        ],
      ),
    );
  }
}

class _ValuePlate extends StatelessWidget {
  const _ValuePlate({required this.label, required this.value, this.width = 72});

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 7),
      decoration: BoxDecoration(
        color: AetherColors.background,
        border: Border.all(color: AetherColors.raised),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: AetherColors.secondaryText, fontSize: 8, letterSpacing: 0.6)),
          const SizedBox(height: 1),
          Text(value, style: const TextStyle(color: AetherColors.paper, fontSize: 11, fontWeight: FontWeight.w600)),
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
          color: primary ? AetherColors.sage.withValues(alpha: 0.15) : AetherColors.panel,
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
  const _StatusBar({
    required this.engineConnected,
    required this.isPlaying,
    required this.engineError,
  });

  final bool engineConnected;
  final bool isPlaying;
  final Object? engineError;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: AetherColors.background,
      child: Row(
        children: [
          Icon(
            Icons.circle,
            color: engineConnected ? AetherColors.sage : AetherColors.magenta,
            size: 6,
          ),
          const SizedBox(width: 6),
          const Text(
            'FLUTTER ALPHA',
            style: TextStyle(color: AetherColors.secondaryText, fontSize: 8, letterSpacing: 0.6),
          ),
          const Spacer(),
          Text(
            engineConnected
                ? (isPlaying ? 'NATIVE ENGINE CONNECTED · PLAYING' : 'NATIVE ENGINE CONNECTED · DEMO CLIPS ONLY')
                : 'ENGINE UNAVAILABLE · DEMO CLIPS ONLY',
            style: const TextStyle(color: AetherColors.secondaryText, fontSize: 8, letterSpacing: 0.4),
          ),
          if (engineError != null) ...[
            const SizedBox(width: 8),
            const Icon(Icons.warning_amber_rounded, color: AetherColors.magenta, size: 11),
          ],
          const SizedBox(width: 8),
          const Text(
            'WINDOWS / macOS',
            style: TextStyle(color: AetherColors.sage, fontSize: 8, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}
