import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';

import 'engine_controller.dart';
import 'native_engine.dart';
import 'session_store.dart';
import 'models.dart';
import 'performance_settings.dart';
import 'widgets/hypnosynth_panel.dart';
import 'theme.dart';
import 'widgets/timeline_view.dart';
import 'widgets/workspace_panels.dart';
import 'waveform_loader.dart';

class AetherbandApp extends StatelessWidget {
  const AetherbandApp({
    this.createEngine,
    this.pickAudioFile,
    this.pickSessionFile,
    this.pickSessionSavePath,
    this.pickExportSavePath,
    this.pickRecordingSavePath,
    super.key,
  });

  final Future<EngineController> Function()? createEngine;
  final Future<XFile?> Function()? pickAudioFile;
  final Future<XFile?> Function()? pickSessionFile;
  final Future<String?> Function()? pickSessionSavePath;
  final Future<String?> Function()? pickExportSavePath;
  final Future<String?> Function()? pickRecordingSavePath;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aetherband',
      debugShowCheckedModeBanner: false,
      theme: AetherTheme.dark,
      home: AetherbandWorkspace(
        createEngine: createEngine,
        pickAudioFile: pickAudioFile,
        pickSessionFile: pickSessionFile,
        pickSessionSavePath: pickSessionSavePath,
        pickExportSavePath: pickExportSavePath,
        pickRecordingSavePath: pickRecordingSavePath,
      ),
    );
  }
}

class AetherbandWorkspace extends StatefulWidget {
  const AetherbandWorkspace({
    this.createEngine,
    this.pickAudioFile,
    this.pickSessionFile,
    this.pickSessionSavePath,
    this.pickExportSavePath,
    this.pickRecordingSavePath,
    super.key,
  });

  final Future<EngineController> Function()? createEngine;
  final Future<XFile?> Function()? pickAudioFile;
  final Future<XFile?> Function()? pickSessionFile;
  final Future<String?> Function()? pickSessionSavePath;
  final Future<String?> Function()? pickExportSavePath;
  final Future<String?> Function()? pickRecordingSavePath;

  @override
  State<AetherbandWorkspace> createState() => _AetherbandWorkspaceState();
}

class _AetherbandWorkspaceState extends State<AetherbandWorkspace> {
  EngineController? _engine;
  Object? _engineError;
  final List<TrackModel> _tracks = [];
  PerformanceSettings _performance = const PerformanceSettings();
  Future<void> _performanceChain = Future.value();
  final Map<String, int> _nativeTrackIds = <String, int>{};
  final Map<String, String> _nativeTrackSources = <String, String>{};
  final Map<String, Timer> _clipPositionTimers = <String, Timer>{};
  final Map<String, double> _confirmedClipStarts = <String, double>{};
  final Map<String, double> _clipMoveStarts = <String, double>{};
  final List<_ClipMoveEdit> _undoClipMoves = <_ClipMoveEdit>[];
  final List<_ClipMoveEdit> _redoClipMoves = <_ClipMoveEdit>[];
  bool _positionMoveDeniedShown = false;
  final AudioSessionStore _sessionStore = const AudioSessionStore();
  final Set<Future<void>> _mixerActions = <Future<void>>{};
  String _sessionTitle = 'Untitled Session';
  String? _sessionPath;
  bool _sessionDirty = false;
  int _sessionRevision = 0;
  int _nextPersistentTrackSerial = 0;
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

  String _selectedTrackId = '';
  String? _selectedClipId;
  String _browserCategory = 'Instruments';
  String _preset = 'Soft Focus';
  bool _browserOpen = true;
  bool _showMixer = false;
  bool _initializingEngine = false;
  bool _trackOperationPending = false;
  bool _importingAudio = false;
  bool _isRecording = false;
  bool _snapToBeat = true;
  String? _recordingPath;
  double _recordingStartSeconds = 0;
  double _zoom = 1;
  double _timelineViewportWidth = 900;
  int? _selectedOutputDeviceIndex;
  String? _selectedOutputDeviceName;

  TrackModel? get _selectedTrack =>
      _tracks.where((track) => track.id == _selectedTrackId).firstOrNull;

  String _createPersistentTrackId() =>
      'native-${DateTime.now().microsecondsSinceEpoch}-${_nextPersistentTrackSerial++}';

  void _markSessionChanged() {
    _sessionRevision++;
    _sessionDirty = true;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_initializeEngine());
  }

  Future<void> _initializeEngine() async {
    if (_isRecording) {
      _showRecordingSessionGuard();
      return;
    }
    if (_initializingEngine || _trackOperationPending) return;
    _initializingEngine = true;

    try {
      // Retry must not orphan an existing native handle or leave its telemetry
      // timer/subscription alive if the error came from polling after startup.
      final previousEngine = _engine;
      _engine = null;
      // A replacement engine has a new inventory; old native IDs must never be
      // reused against it or leave silent clips looking loaded.
      setState(() {
        _tracks.removeWhere((track) => _nativeTrackIds.containsKey(track.id));
        _nativeTrackIds.clear();
        _nativeTrackSources.clear();
        _clipMoveStarts.clear();
        _undoClipMoves.clear();
        _redoClipMoves.clear();
        for (final timer in _clipPositionTimers.values) {
          timer.cancel();
        }
        _clipPositionTimers.clear();
        _confirmedClipStarts.clear();
        // The replacement engine has no imported media inventory. Never keep
        // showing a previously loaded project as if it were still available.
        _sessionPath = null;
        _sessionTitle = 'Untitled Session';
        _sessionDirty = false;
        if (!_tracks.any((track) => track.id == _selectedTrackId)) {
          _selectedTrackId = _tracks.isEmpty ? '' : _tracks.first.id;
          _selectedClipId = null;
        }
        _telemetry = const EngineTelemetry(
          playheadSeconds: 0,
          sampleRateHz: 0,
          peakLeft: 0,
          peakRight: 0,
          isPlaying: false,
        );
      });
      await _telemetrySubscription?.cancel();
      _telemetrySubscription = null;
      if (previousEngine != null) await previousEngine.dispose();

      final engine =
          await (widget.createEngine ?? NativeEngineController.create)();
      if (!mounted) {
        await engine.dispose();
        return;
      }
      _engine = engine;
      _telemetrySubscription = engine.telemetry.listen(
        (value) {
          if (mounted) setState(() => _telemetry = value);
        },
        onError: (Object error) {
          if (mounted) setState(() => _engineError = error);
        },
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
    for (final timer in _clipPositionTimers.values) {
      timer.cancel();
    }
    _clipPositionTimers.clear();
    final engine = _engine;
    if (engine != null) unawaited(engine.dispose());
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_trackOperationPending || _initializingEngine) return;
    final engine = _engine;
    if (engine == null) {
      _showEngineUnavailable();
      return;
    }
    try {
      if (_telemetry.isPlaying) {
        await engine.pause();
      } else {
        await engine.play();
      }
    } catch (error) {
      if (mounted) setState(() => _engineError = error);
    }
  }

  Future<void> _stop() async {
    final engine = _engine;
    if (engine == null) {
      _showEngineUnavailable();
      return;
    }
    try {
      await engine.stop();
    } catch (error) {
      if (mounted) setState(() => _engineError = error);
    }
  }

  Future<void> _goToStart() async {
    if (_isRecording) {
      _showRecordingSessionGuard();
      return;
    }
    await _stop();
  }

  void _zoomToFit() {
    final tempo = _performance.tempo.round();
    final clipEnd = _tracks.expand((track) => track.clips).fold<double>(
          0,
          (end, clip) => math.max(
            end,
            clip.timelineLeft(tempo) + clip.timelineWidth(tempo),
          ),
        );
    final contentWidth = math.max(1400.0, clipEnd + 84);
    setState(() {
      _zoom =
          (_timelineViewportWidth / contentWidth).clamp(0.2, 1.5).toDouble();
    });
  }

  bool _rejectSessionChangeDuringRecording() {
    if (!_isRecording) return false;
    _showRecordingSessionGuard();
    return true;
  }

  void _showRecordingSessionGuard() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Stop recording before changing or saving this session.'),
      ),
    );
  }

  void _showEngineUnavailable() {
    final message =
        _engineError?.toString() ?? 'Native audio engine is not ready.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showFeatureUnavailable(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '$feature is not implemented yet; no recording or project changes were made.'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _loadClipWaveform(
      TrackModel track, ClipModel clip, String path) async {
    List<double>? peaks;
    try {
      peaks = await loadWaveformPeaks(path);
    } on Object {
      // A worker-isolate failure must not surface as an unhandled UI error.
    }
    if (!mounted) return;
    if (!_tracks.any(
        (active) => active.id == track.id && active.clips.contains(clip))) {
      return;
    }
    setState(() {
      clip.waveformPeaks = peaks;
      clip.waveformLoaded = true;
    });
  }

  Future<void> _importAudio() async {
    if (_trackOperationPending || _initializingEngine) return;
    final engine = _engine;
    if (engine == null) {
      _showEngineUnavailable();
      return;
    }
    const audioTypes = XTypeGroup(
      label: 'Audio',
      extensions: <String>['wav', 'aiff', 'aif', 'flac', 'mp3', 'ogg', 'm4a'],
    );
    setState(() {
      _trackOperationPending = true;
      _importingAudio = true;
    });
    try {
      final file = await (widget.pickAudioFile?.call() ??
          openFile(acceptedTypeGroups: <XTypeGroup>[audioTypes]));
      if (file == null || !mounted) return;
      // Loaded tracks currently start at frame zero; rewind before import so
      // their displayed origin matches playback instead of joining mid-session.
      await engine.stop();
      if (!mounted) return;
      final loaded = await engine.loadTrack(file.path);
      if (!mounted) return;
      final nativeId = loaded.id;
      final name = file.name;
      final id = _createPersistentTrackId();
      final clip = ClipModel(
        id: '$id-clip',
        title: name,
        start: 0,
        width: 0,
        color: AetherColors.sage,
        isDemo: false,
        durationSeconds: loaded.durationSeconds,
      );
      final track = TrackModel(
        id: id,
        name: name,
        kind: 'AUDIO',
        color: AetherColors.sage,
        volume: 0.8,
        pan: 0.5,
        clips: <ClipModel>[clip],
      );
      setState(() {
        _nativeTrackIds[id] = nativeId;
        _nativeTrackSources[id] = file.path;
        _showMixer = true;
        _markSessionChanged();
        _tracks.add(track);
        _selectedTrackId = id;
        _selectedClipId = '$id-clip';
        _engineError = null;
      });
      unawaited(_loadClipWaveform(track, clip, file.path));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio import failed: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _trackOperationPending = false;
          _importingAudio = false;
        });
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_trackOperationPending || _initializingEngine) return;
    final engine = _engine;
    if (engine == null || engine is! AudioRecordingEngine) {
      _showFeatureUnavailable('Windows audio input recording');
      return;
    }
    final recordingEngine = engine as AudioRecordingEngine;

    if (!_isRecording) {
      final selectedPath = widget.pickRecordingSavePath != null
          ? await widget.pickRecordingSavePath!()
          : (await getSaveLocation(
              suggestedName: '$_sessionTitle take.wav',
              acceptedTypeGroups: const <XTypeGroup>[
                XTypeGroup(label: 'WAV recording', extensions: ['wav']),
              ],
            ))
              ?.path;
      if (selectedPath == null || !mounted) return;
      final path = selectedPath.toLowerCase().endsWith('.wav')
          ? selectedPath
          : '$selectedPath.wav';
      final startSeconds = _telemetry.playheadSeconds;
      setState(() => _trackOperationPending = true);
      try {
        await recordingEngine.startRecording(path);
        if (!mounted) return;
        setState(() {
          _isRecording = true;
          _recordingPath = path;
          _recordingStartSeconds = startSeconds;
          _engineError = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording input to $path')),
        );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not start recording: $error')),
          );
        }
      } finally {
        if (mounted) setState(() => _trackOperationPending = false);
      }
      return;
    }

    final path = _recordingPath;
    if (path == null) {
      setState(() => _isRecording = false);
      return;
    }
    setState(() => _trackOperationPending = true);
    try {
      final stats = await recordingEngine.stopRecording();
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordingPath = null;
        });
      }
      final loaded = await engine.loadTrack(path);
      await engine.setTrackStartSeconds(loaded.id, _recordingStartSeconds);
      if (!mounted) return;
      _registerRecordedTrack(path, loaded, _recordingStartSeconds);
      final dropped = stats.framesDropped;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dropped == 0
                ? 'Recording added as a ${stats.sampleRateHz} Hz audio track.'
                : 'Recording added; $dropped input frames were dropped.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordingPath = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not finish recording: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _trackOperationPending = false);
    }
  }

  void _registerRecordedTrack(
    String path,
    LoadedAudioTrack loaded,
    double startSeconds,
  ) {
    final name = File(path).uri.pathSegments.last;
    final id = _createPersistentTrackId();
    final clip = ClipModel(
      id: '$id-clip',
      title: name,
      start: 0,
      width: 0,
      color: AetherColors.sage,
      isDemo: false,
      durationSeconds: loaded.durationSeconds,
      startSeconds: startSeconds,
    );
    final track = TrackModel(
      id: id,
      name: name,
      kind: 'AUDIO',
      color: AetherColors.sage,
      volume: 0.8,
      pan: 0.5,
      clips: <ClipModel>[clip],
    );
    setState(() {
      _nativeTrackIds[id] = loaded.id;
      _nativeTrackSources[id] = path;
      _showMixer = true;
      _markSessionChanged();
      _tracks.add(track);
      _selectedTrackId = id;
      _selectedClipId = '$id-clip';
    });
    unawaited(_loadClipWaveform(track, clip, path));
  }

  Future<void> _removeSelectedTrack() async {
    if (_trackOperationPending || _initializingEngine) return;
    final engine = _engine;
    final selectedId = _selectedTrackId;
    final nativeId = _nativeTrackIds[selectedId];
    if (engine == null || nativeId == null) {
      _showFeatureUnavailable('Removing demo tracks');
      return;
    }
    setState(() => _trackOperationPending = true);
    try {
      await engine.removeTrack(nativeId);
      if (!mounted) return;
      setState(() {
        final removedTrack =
            _tracks.where((track) => track.id == selectedId).firstOrNull;
        _tracks.removeWhere((track) => track.id == selectedId);
        _nativeTrackIds.remove(selectedId);
        _nativeTrackSources.remove(selectedId);
        if (removedTrack != null) {
          for (final clip in removedTrack.clips) {
            _clipPositionTimers.remove(clip.id)?.cancel();
            _confirmedClipStarts.remove(clip.id);
            _clipMoveStarts.remove(clip.id);
          }
        }
        _undoClipMoves.removeWhere((edit) => edit.trackId == selectedId);
        _redoClipMoves.removeWhere((edit) => edit.trackId == selectedId);
        _markSessionChanged();
        if (_selectedTrackId == selectedId) {
          _selectedTrackId = _tracks.isEmpty ? '' : _tracks.first.id;
          _selectedClipId = null;
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Track removal failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _trackOperationPending = false);
    }
  }

  Future<void> _duplicateSelectedTrack() async {
    if (_trackOperationPending || _initializingEngine) return;
    final engine = _engine;
    final selected = _selectedTrack;
    final source = selected == null ? null : _nativeTrackSources[selected.id];
    final clip = selected?.clips.firstOrNull;
    if (engine == null || selected == null || source == null || clip == null) {
      _showFeatureUnavailable('Duplicating demo or instrument tracks');
      return;
    }

    setState(() => _trackOperationPending = true);
    int? uncommittedNativeId;
    var adopted = false;
    try {
      if (await engine.getTrackCount() >= AudioSessionDocument.maxTracks) {
        throw StateError(
            'A session can contain at most ${AudioSessionDocument.maxTracks} audio tracks.');
      }
      final loaded = await engine.loadTrack(source);
      uncommittedNativeId = loaded.id;
      await engine.setTrackVolume(loaded.id, selected.volume);
      await engine.setTrackPan(loaded.id, selected.pan);
      await engine.muteTrack(loaded.id, selected.muted);
      await engine.soloTrack(loaded.id, selected.solo);
      await engine.setTrackStartSeconds(loaded.id, clip.startSeconds);

      final id = _createPersistentTrackId();
      final suffix = ' copy';
      final name = selected.name.length + suffix.length <= 120
          ? '${selected.name}$suffix'
          : '${selected.name.substring(0, 120 - suffix.length)}$suffix';
      final duplicateClip = ClipModel(
        id: '$id-clip',
        title: clip.title,
        start: 0,
        width: 0,
        color: selected.color,
        isDemo: false,
        durationSeconds: loaded.durationSeconds,
        startSeconds: clip.startSeconds,
        waveformPeaks: clip.waveformPeaks == null
            ? null
            : List<double>.of(clip.waveformPeaks!),
        waveformLoaded: clip.waveformLoaded,
      );
      final duplicate = TrackModel(
        id: id,
        name: name,
        kind: selected.kind,
        color: selected.color,
        clips: <ClipModel>[duplicateClip],
        muted: selected.muted,
        solo: selected.solo,
        volume: selected.volume,
        pan: selected.pan,
      );
      if (!mounted) return;
      setState(() {
        _nativeTrackIds[id] = loaded.id;
        _nativeTrackSources[id] = source;
        _tracks.add(duplicate);
        _selectedTrackId = id;
        _selectedClipId = duplicateClip.id;
        _markSessionChanged();
      });
      adopted = true;
      uncommittedNativeId = null;
      unawaited(_loadClipWaveform(duplicate, duplicateClip, source));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Track duplication failed: $error')),
        );
      }
    } finally {
      if (!adopted && uncommittedNativeId != null) {
        try {
          await engine.removeTrack(uncommittedNativeId);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'The duplicate could not be added, and its temporary audio track could not be removed.'),
            ));
          }
        }
      }
      if (mounted) setState(() => _trackOperationPending = false);
    }
  }

  Future<void> _renameSelectedTrack() async {
    final selected = _selectedTrack;
    if (selected == null || !_nativeTrackSources.containsKey(selected.id)) {
      _showFeatureUnavailable('Renaming demo or instrument tracks');
      return;
    }
    var draft = selected.name;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename audio track'),
        content: TextFormField(
          key: const ValueKey('rename-track-name'),
          initialValue: selected.name,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Track name'),
          onChanged: (value) => draft = value,
          onFieldSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(dialogContext, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (draft.trim().isNotEmpty) {
                Navigator.pop(dialogContext, draft);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    final name = result?.trim();
    if (!mounted || name == null || name.isEmpty) return;
    if (!_tracks.contains(selected)) return;
    setState(() {
      selected.name = name;
      _markSessionChanged();
    });
  }

  AudioSessionDocument _captureAudioSession(String title) {
    final tracks = <SavedAudioTrack>[];
    for (final track in _tracks) {
      final path = _nativeTrackSources[track.id];
      if (path == null) continue; // Deliberately exclude visual demo content.
      tracks.add(SavedAudioTrack(
        id: track.id,
        name: track.name,
        sourceUri: File(path).absolute.uri.toString(),
        gain: track.volume,
        pan: track.pan,
        muted: track.muted,
        solo: track.solo,
        startSeconds: track.clips.firstOrNull?.startSeconds ?? 0,
      ));
    }
    return AudioSessionDocument(
        title: title, tracks: tracks, performance: _performance);
  }

  String _titleFromSessionPath(String path) {
    final name = File(path).absolute.uri.pathSegments.last;
    const extension = '.aetherband.json';
    final result = name.endsWith(extension)
        ? name.substring(0, name.length - extension.length)
        : (name.endsWith('.json') ? name.substring(0, name.length - 5) : name);
    if (result.trim().isEmpty) return 'Untitled Session';
    return result.length > 120 ? result.substring(0, 120) : result;
  }

  Future<String?> _chooseSessionSavePath() async {
    if (widget.pickSessionSavePath != null) {
      return widget.pickSessionSavePath!();
    }
    final location = await getSaveLocation(
      suggestedName: '$_sessionTitle.aetherband.json',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'Aetherband session', extensions: ['json']),
      ],
    );
    if (location == null) return null;
    return location.path.endsWith('.json')
        ? location.path
        : '${location.path}.aetherband.json';
  }

  Future<void> _flushPendingMixerActions() async {
    // Clip drags update visually first and debounce their native position
    // command. Flush before either saving or rendering the engine's snapshot.
    for (final entry in _clipPositionTimers.entries.toList()) {
      entry.value.cancel();
      final clip = _tracks
          .expand((track) => track.clips)
          .where((clip) => clip.id == entry.key)
          .firstOrNull;
      final track = clip == null
          ? null
          : _tracks.where((track) => track.clips.contains(clip)).firstOrNull;
      final nativeId = track == null ? null : _nativeTrackIds[track.id];
      final engine = _engine;
      if (clip != null && track != null && nativeId != null && engine != null) {
        _queueMixerAction(
          _commitClipStart(engine, track, clip, nativeId, clip.startSeconds),
        );
      }
    }
    _clipPositionTimers.clear();
    if (_mixerActions.isNotEmpty) {
      await Future.wait(_mixerActions.toList());
    }
  }

  Future<void> _saveSession({bool saveAs = false}) async {
    if (_rejectSessionChangeDuringRecording()) return;
    if (_trackOperationPending || _initializingEngine) return;
    var path = saveAs ? null : _sessionPath;
    if (path == null) {
      path = await _chooseSessionSavePath();
      if (path == null || !mounted) return;
    }
    setState(() => _trackOperationPending = true);
    try {
      // Do not write optimistic fader values while a native rejection is
      // still possible. No further mixer edits are admitted during the save.
      await _flushPendingMixerActions();
      if (!mounted) return;
      final title = _titleFromSessionPath(path);
      final document = _captureAudioSession(title);
      final revisionAtSave = _sessionRevision;
      await _sessionStore.save(path, document);
      if (!mounted) return;
      setState(() {
        _sessionTitle = title;
        _sessionPath = path;
        if (_sessionRevision == revisionAtSave) {
          _sessionDirty = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Saved ${document.tracks.length} real audio tracks. '
          'Demo clips and unsupported edits are not included.',
        ),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Session save failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _trackOperationPending = false);
    }
  }

  Future<void> _exportMixdown() async {
    if (_trackOperationPending || _initializingEngine) return;
    final engine = _engine;
    if (engine is! ExportEngine) {
      _showFeatureUnavailable(
          'Mixdown export requires the Windows audio engine');
      return;
    }
    final exportEngine = engine as ExportEngine;
    final selectedPath = widget.pickExportSavePath != null
        ? await widget.pickExportSavePath!()
        : (await getSaveLocation(
            suggestedName: '$_sessionTitle.wav',
            acceptedTypeGroups: const <XTypeGroup>[
              XTypeGroup(label: 'WAV audio', extensions: ['wav']),
            ],
          ))
            ?.path;
    if (selectedPath == null || !mounted) return;
    final path = selectedPath.toLowerCase().endsWith('.wav')
        ? selectedPath
        : '$selectedPath.wav';
    setState(() => _trackOperationPending = true);
    try {
      await _flushPendingMixerActions();
      if (!mounted) return;
      await exportEngine.exportWav(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stereo WAV exported to $path')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mixdown export failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _trackOperationPending = false);
    }
  }

  Future<bool> _confirmDiscardChanges() async {
    if (!_sessionDirty) return true;
    final choice = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unsaved audio session changes'),
        content: const Text(
          'Opening or creating another session will discard unsaved '
          'imported audio track and mixer changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    return choice == true;
  }

  Future<void> _adoptPreparedSession({
    required EngineController preparedEngine,
    required List<TrackModel> preparedTracks,
    required Map<String, int> preparedIds,
    required Map<String, String> preparedSources,
    required String title,
    required String? path,
    PerformanceSettings performance = const PerformanceSettings(),
  }) async {
    final previousEngine = _engine;
    if (identical(preparedEngine, previousEngine)) {
      throw StateError('A session must use a new native engine instance.');
    }
    await _telemetrySubscription?.cancel();
    if (!mounted) return;
    _telemetrySubscription = preparedEngine.telemetry.listen(
      (value) {
        if (mounted) setState(() => _telemetry = value);
      },
      onError: (Object error) {
        if (mounted) setState(() => _engineError = error);
      },
    );
    setState(() {
      _engine = preparedEngine;
      _performance = performance;
      _tracks.removeWhere((track) => _nativeTrackIds.containsKey(track.id));
      _tracks.addAll(preparedTracks);
      _showMixer = preparedTracks.isNotEmpty;
      _nativeTrackIds
        ..clear()
        ..addAll(preparedIds);
      _nativeTrackSources
        ..clear()
        ..addAll(preparedSources);
      for (final timer in _clipPositionTimers.values) {
        timer.cancel();
      }
      _clipPositionTimers.clear();
      _clipMoveStarts.clear();
      _undoClipMoves.clear();
      _redoClipMoves.clear();
      _confirmedClipStarts
        ..clear()
        ..addEntries(preparedTracks.expand((track) => track.clips.map(
              (clip) => MapEntry(clip.id, clip.startSeconds),
            )));
      _selectedTrackId = preparedTracks.isEmpty ? '' : preparedTracks.first.id;
      _selectedClipId =
          preparedTracks.isEmpty ? null : preparedTracks.first.clips.first.id;
      _sessionTitle = title;
      _sessionPath = path;
      _sessionDirty = false;
      _sessionRevision++;
      _engineError = null;
      _telemetry = const EngineTelemetry(
        playheadSeconds: 0,
        sampleRateHz: 0,
        peakLeft: 0,
        peakRight: 0,
        isPlaying: false,
      );
    });
    if (previousEngine != null) {
      try {
        await previousEngine.dispose();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Old engine cleanup warning: $error')),
          );
        }
      }
    }
  }

  Future<void> _openSession() async {
    if (_rejectSessionChangeDuringRecording()) return;
    if (_trackOperationPending || _initializingEngine) return;
    if (!await _confirmDiscardChanges() || !mounted) return;
    final file = await (widget.pickSessionFile?.call() ??
        openFile(acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'Aetherband session', extensions: ['json']),
        ]));
    if (file == null || !mounted) return;

    setState(() => _trackOperationPending = true);
    EngineController? staged;
    try {
      // This validates JSON, version and source-file existence before any
      // existing session state is modified.
      final document = await _sessionStore.open(file.path);
      if (!mounted) return;
      staged = await (widget.createEngine ?? NativeEngineController.create)();
      if (identical(staged, _engine)) {
        throw StateError(
            'Cannot reuse an active native engine for project staging.');
      }
      if (staged is! PerformanceEngine) {
        throw StateError('This engine does not support HypnoSynth settings.');
      }
      await _applyPerformance(
          staged as PerformanceEngine, document.performance);
      final tracks = <TrackModel>[];
      final ids = <String, int>{};
      final sources = <String, String>{};
      for (final saved in document.tracks) {
        final source = saved.sourcePath;
        final loaded = await staged.loadTrack(source);
        await staged.setTrackVolume(loaded.id, saved.gain);
        await staged.setTrackPan(loaded.id, saved.pan);
        await staged.muteTrack(loaded.id, saved.muted);
        await staged.soloTrack(loaded.id, saved.solo);
        await staged.setTrackStartSeconds(loaded.id, saved.startSeconds);
        ids[saved.id] = loaded.id;
        sources[saved.id] = source;
        final clip = ClipModel(
          id: '${saved.id}-clip',
          title: saved.name,
          start: 0,
          width: 0,
          color: AetherColors.sage,
          isDemo: false,
          durationSeconds: loaded.durationSeconds,
          startSeconds: saved.startSeconds,
        );
        tracks.add(TrackModel(
          id: saved.id,
          name: saved.name,
          kind: 'AUDIO',
          color: AetherColors.sage,
          volume: saved.gain,
          pan: saved.pan,
          muted: saved.muted,
          solo: saved.solo,
          clips: [clip],
        ));
      }
      if (!mounted) return;
      await _adoptPreparedSession(
        preparedEngine: staged,
        preparedTracks: tracks,
        preparedIds: ids,
        preparedSources: sources,
        title: document.title,
        path: file.path,
        performance: document.performance,
      );
      staged = null; // Ownership now belongs to the workspace.
      for (final track in tracks) {
        final source = sources[track.id];
        final clip = track.clips.firstOrNull;
        if (source != null && clip != null) {
          unawaited(_loadClipWaveform(track, clip, source));
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opened ${tracks.length} audio tracks.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Session open failed: $error')),
        );
      }
    } finally {
      // An unsuccessful staged load never destroys the previous session.
      if (staged != null && !identical(staged, _engine)) {
        await staged.dispose();
      }
      if (mounted) setState(() => _trackOperationPending = false);
    }
  }

  Future<void> _newSession() async {
    if (_rejectSessionChangeDuringRecording()) return;
    if (_trackOperationPending || _initializingEngine) return;
    if (!await _confirmDiscardChanges() || !mounted) return;
    setState(() => _trackOperationPending = true);
    EngineController? staged;
    try {
      staged = await (widget.createEngine ?? NativeEngineController.create)();
      if (identical(staged, _engine)) {
        throw StateError(
            'Cannot reuse an active native engine for a new session.');
      }
      if (!mounted) return;
      await _adoptPreparedSession(
        preparedEngine: staged,
        preparedTracks: const [],
        preparedIds: const {},
        preparedSources: const {},
        title: 'Untitled Session',
        path: null,
      );
      staged = null;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('New session failed: $error')),
        );
      }
    } finally {
      if (staged != null && !identical(staged, _engine)) {
        await staged.dispose();
      }
      if (mounted) setState(() => _trackOperationPending = false);
    }
  }

  Future<void> _applyPerformance(
    PerformanceEngine engine,
    PerformanceSettings settings, {
    PerformanceSettings? previous,
  }) async {
    if (previous == null || previous.preset != settings.preset) {
      await engine.synthEvent(2, settings.preset, 0);
    }
    for (var i = 0; i < 5; i++) {
      if (previous == null || previous.macros[i] != settings.macros[i]) {
        await engine.synthEvent(3, i, settings.macros[i]);
      }
    }
    for (var i = 0; i < settings.sequenceNotes.length; i++) {
      if (previous == null ||
          previous.sequenceNotes[i] != settings.sequenceNotes[i]) {
        await engine.synthEvent(
          5,
          i,
          settings.sequenceNotes[i]?.toDouble() ?? -1,
        );
      }
    }
    if (previous == null ||
        previous.tempo != settings.tempo ||
        previous.metronome != settings.metronome ||
        previous.sequence != settings.sequence) {
      await engine.configureTransport(
          settings.tempo, settings.metronome, settings.sequence);
    }
    if (previous == null || previous.master != settings.master) {
      await engine.setMasterVolume(settings.master);
    }
  }

  void _changePerformance(PerformanceSettings settings) {
    final engine = _engine;
    if (engine == null ||
        engine is! PerformanceEngine ||
        _trackOperationPending ||
        _initializingEngine) {
      return;
    }
    final performance = engine as PerformanceEngine;
    final previous = _performance;
    setState(() {
      _performance = settings;
      _markSessionChanged();
    });
    final action = _performanceChain
        .then((_) => _applyPerformance(
              performance,
              settings,
              previous: previous,
            ))
        .catchError((Object error) {
      if (mounted && identical(_performance, settings)) {
        setState(() => _performance = previous);
      }
      _reportMixerFailure('Instrument settings', error);
    });
    _performanceChain = action;
    _mixerActions.add(action);
    unawaited(action.whenComplete(() => _mixerActions.remove(action)));
  }

  Future<void> _sendSynth(int event, int key, double value) async {
    final engine = _engine;
    if (engine == null ||
        engine is! PerformanceEngine ||
        _trackOperationPending ||
        _initializingEngine) {
      return;
    }
    try {
      await (engine as PerformanceEngine).synthEvent(event, key, value);
    } catch (error) {
      _reportMixerFailure('HypnoSynth', error);
    }
  }

  Future<void> _auditionSynth() async {
    _changePerformance(_performance.copyWith(sequence: true));
    await _performanceChain;
    if (!_telemetry.isPlaying) await _togglePlay();
  }

  void _handleMenuCommand(_MenuAction action) {
    switch (action.id) {
      case 'edit.undo':
        unawaited(_undoClipMove());
        return;
      case 'edit.redo':
        unawaited(_redoClipMove());
        return;
      case 'file.new':
        unawaited(_newSession());
        return;
      case 'file.open':
        unawaited(_openSession());
        return;
      case 'file.save':
        unawaited(_saveSession());
        return;
      case 'file.saveAs':
        unawaited(_saveSession(saveAs: true));
        return;
      case 'file.export':
        unawaited(_exportMixdown());
        return;
      case 'audio.output':
        unawaited(_chooseOutputDevice());
        return;
      case 'view.browser':
        setState(() => _browserOpen = !_browserOpen);
        return;
      case 'view.mixer':
        setState(() => _showMixer = !_showMixer);
        return;
      case 'view.zoomToFit':
        _zoomToFit();
        return;
      case 'track.addInstrument':
        setState(() => _showMixer = false);
        return;
      case 'track.addAudio':
        unawaited(_importAudio());
        return;
      case 'track.delete':
        unawaited(_removeSelectedTrack());
        return;
      case 'track.duplicate':
        unawaited(_duplicateSelectedTrack());
        return;
      case 'track.rename':
        unawaited(_renameSelectedTrack());
        return;
      case 'transport.play':
        unawaited(_togglePlay());
        return;
      case 'transport.stop':
        unawaited(_stop());
        return;
      case 'navigate.start':
        unawaited(_goToStart());
        return;
      case 'transport.record':
        unawaited(_toggleRecording());
        return;
      case 'record.metronome':
        _changePerformance(
            _performance.copyWith(metronome: !_performance.metronome));
        return;
      case 'record.countIn':
        _showFeatureUnavailable('Count-in recording');
        return;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${action.label} is not connected in this UI prototype yet.'),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  Future<void> _chooseOutputDevice() async {
    final engine = _engine;
    if (engine == null || engine is! AudioOutputEngine) {
      _showFeatureUnavailable('Windows audio output selection');
      return;
    }
    final outputEngine = engine as AudioOutputEngine;
    try {
      final devices = await outputEngine.getOutputDevices();
      if (!mounted) return;
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No Windows audio output devices were found.'),
        ));
        return;
      }
      final selected = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Audio Output'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final device in devices)
                  ListTile(
                    title: Text(device.name),
                    subtitle: Text(
                        '${device.sampleRateHz} Hz · ${device.channels} channels${device.isDefault ? ' · Windows default' : ''}'),
                    trailing: _selectedOutputDeviceIndex == device.index ||
                            (_selectedOutputDeviceIndex == null &&
                                device.isDefault)
                        ? const Icon(Icons.check, color: AetherColors.sage)
                        : null,
                    onTap: () => Navigator.pop(dialogContext, device.index),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (selected == null) return;
      await outputEngine.selectOutputDevice(selected);
      final device = devices.firstWhere((value) => value.index == selected);
      if (!mounted) return;
      setState(() {
        _selectedOutputDeviceIndex = selected;
        _selectedOutputDeviceName = device.name;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Audio output: ${device.name}. Playback stops and returns to the start when the output changes.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not change audio output: $error')),
      );
    }
  }

  void _moveClip(TrackModel track, ClipModel clip, double deltaPx) {
    if (clip.isDemo) {
      setState(() {
        clip.start =
            (clip.start + deltaPx / _zoom).clamp(0.0, 2200.0).toDouble();
        _selectedTrackId = track.id;
        _selectedClipId = clip.id;
      });
      return;
    }
    if (_telemetry.isPlaying || _telemetry.playheadSeconds > 0) {
      if (!_positionMoveDeniedShown) {
        _positionMoveDeniedShown = true;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Stop playback before moving an audio clip.'),
        ));
        Timer(
          const Duration(seconds: 2),
          () => _positionMoveDeniedShown = false,
        );
      }
      return;
    }
    final nativeId = _nativeTrackIds[track.id];
    final engine = _engine;
    if (nativeId == null || engine == null || _trackOperationPending) return;
    final pixelsPerSecond = timelinePixelsPerSecond(_performance.tempo);
    final beatSeconds = 60 / _performance.tempo;
    final unsnapped = clip.startSeconds + deltaPx / _zoom / pixelsPerSecond;
    final positioned = _snapToBeat
        ? (unsnapped / beatSeconds).round() * beatSeconds
        : unsnapped;
    final next = positioned.clamp(0.0, 3600.0).toDouble();
    setState(() {
      clip.startSeconds = next;
      _selectedTrackId = track.id;
      _selectedClipId = clip.id;
      _markSessionChanged();
    });
    _clipPositionTimers.remove(clip.id)?.cancel();
    _clipPositionTimers[clip.id] = Timer(const Duration(milliseconds: 60), () {
      _clipPositionTimers.remove(clip.id);
      _queueMixerAction(_commitClipStart(engine, track, clip, nativeId, next));
    });
  }

  void _beginClipMove(TrackModel track, ClipModel clip) {
    if (!clip.isDemo) _clipMoveStarts[clip.id] = clip.startSeconds;
  }

  void _finishClipMove(TrackModel track, ClipModel clip) {
    final before = _clipMoveStarts.remove(clip.id);
    if (before == null ||
        clip.isDemo ||
        (clip.startSeconds - before).abs() < 1e-9) {
      return;
    }
    final nativeId = _nativeTrackIds[track.id];
    final engine = _engine;
    if (nativeId == null || engine == null) return;
    _clipPositionTimers.remove(clip.id)?.cancel();
    final edit = _ClipMoveEdit(
      trackId: track.id,
      clipId: clip.id,
      beforeSeconds: before,
      afterSeconds: clip.startSeconds,
    );
    _queueMixerAction(_commitClipStart(
        engine, track, clip, nativeId, edit.afterSeconds,
        historyEdit: edit));
  }

  Future<void> _undoClipMove() => _applyClipMoveHistory(
        source: _undoClipMoves,
        destination: _redoClipMoves,
        target: (edit) => edit.beforeSeconds,
        emptyMessage: 'There is no clip move to undo.',
      );

  Future<void> _redoClipMove() => _applyClipMoveHistory(
        source: _redoClipMoves,
        destination: _undoClipMoves,
        target: (edit) => edit.afterSeconds,
        emptyMessage: 'There is no clip move to redo.',
      );

  Future<void> _applyClipMoveHistory({
    required List<_ClipMoveEdit> source,
    required List<_ClipMoveEdit> destination,
    required double Function(_ClipMoveEdit) target,
    required String emptyMessage,
  }) async {
    if (_trackOperationPending || _initializingEngine) return;
    if (source.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(emptyMessage)));
      return;
    }
    if (_telemetry.isPlaying || _telemetry.playheadSeconds > 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Stop playback before undoing or redoing a clip move.'),
      ));
      return;
    }
    final engine = _engine;
    final edit = source.removeLast();
    final track = _tracks.where((item) => item.id == edit.trackId).firstOrNull;
    final clip =
        track?.clips.where((item) => item.id == edit.clipId).firstOrNull;
    final nativeId = track == null ? null : _nativeTrackIds[track.id];
    if (engine == null || track == null || clip == null || nativeId == null) {
      source.add(edit);
      _showEngineUnavailable();
      return;
    }
    final previous = clip.startSeconds;
    final next = target(edit);
    _clipPositionTimers.remove(clip.id)?.cancel();
    setState(() {
      clip.startSeconds = next;
      _markSessionChanged();
    });
    try {
      await engine.setTrackStartSeconds(nativeId, next);
      _confirmedClipStarts[clip.id] = next;
      destination.add(edit);
    } catch (error) {
      if (mounted && _nativeTrackIds[track.id] == nativeId) {
        setState(() => clip.startSeconds = previous);
      }
      source.add(edit);
      _reportMixerFailure('Clip move history', error);
    }
  }

  Future<void> _commitClipStart(
    EngineController engine,
    TrackModel track,
    ClipModel clip,
    int nativeId,
    double seconds, {
    _ClipMoveEdit? historyEdit,
  }) async {
    final previous = _confirmedClipStarts[clip.id] ?? 0;
    try {
      await engine.setTrackStartSeconds(nativeId, seconds);
      _confirmedClipStarts[clip.id] = seconds;
      if (historyEdit != null) {
        _undoClipMoves.add(historyEdit);
        if (_undoClipMoves.length > 100) _undoClipMoves.removeAt(0);
        _redoClipMoves.clear();
      }
    } catch (error) {
      if (!mounted) return;
      if (_nativeTrackIds[track.id] == nativeId &&
          (clip.startSeconds - seconds).abs() < 0.000001) {
        setState(() => clip.startSeconds = previous);
      }
      if (historyEdit != null) {
        final index = _undoClipMoves.lastIndexWhere((edit) =>
            edit.trackId == historyEdit.trackId &&
            edit.clipId == historyEdit.clipId &&
            edit.afterSeconds == historyEdit.afterSeconds);
        if (index >= 0) _undoClipMoves.removeAt(index);
      }
      _reportMixerFailure('Clip position', error);
    }
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

  // Native operations are asynchronous; the UI responds immediately, while
  // rejecting operations roll back the value if it has not since changed.
  // This keeps control errors visible rather than silently pretending success.
  void _reportMixerFailure(String label, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label failed: $error')),
    );
  }

  void _queueMixerAction(Future<void> action) {
    _mixerActions.add(action);
    unawaited(action.whenComplete(() => _mixerActions.remove(action)));
  }

  void _setTrackVolume(TrackModel track, double value) {
    final id = _nativeTrackIds[track.id];
    final engine = _engine;
    if (id != null && engine == null) {
      _showEngineUnavailable();
      return;
    }
    if (_trackOperationPending) return;
    final previous = track.volume;
    setState(() {
      track.volume = value;
      if (id != null) _markSessionChanged();
    });
    if (id != null) {
      _queueMixerAction(_commitVolume(engine!, track, id, value, previous));
    }
  }

  Future<void> _commitVolume(EngineController engine, TrackModel track, int id,
      double value, double previous) async {
    try {
      await engine.setTrackVolume(id, value);
    } catch (error) {
      if (!mounted) return;
      if (_nativeTrackIds[track.id] == id && track.volume == value) {
        setState(() => track.volume = previous);
      }
      _reportMixerFailure('Track volume', error);
    }
  }

  void _setTrackPan(TrackModel track, double value) {
    final id = _nativeTrackIds[track.id];
    final engine = _engine;
    if (id != null && engine == null) {
      _showEngineUnavailable();
      return;
    }
    if (_trackOperationPending) return;
    final previous = track.pan;
    setState(() {
      track.pan = value;
      if (id != null) _markSessionChanged();
    });
    if (id != null) {
      _queueMixerAction(_commitPan(engine!, track, id, value, previous));
    }
  }

  Future<void> _commitPan(EngineController engine, TrackModel track, int id,
      double value, double previous) async {
    try {
      await engine.setTrackPan(id, value);
    } catch (error) {
      if (!mounted) return;
      if (_nativeTrackIds[track.id] == id && track.pan == value) {
        setState(() => track.pan = previous);
      }
      _reportMixerFailure('Track pan', error);
    }
  }

  void _setTrackMute(TrackModel track, bool value) {
    final id = _nativeTrackIds[track.id];
    final engine = _engine;
    if (id != null && engine == null) {
      _showEngineUnavailable();
      return;
    }
    if (_trackOperationPending) return;
    final previous = track.muted;
    setState(() {
      track.muted = value;
      if (id != null) _markSessionChanged();
    });
    if (id != null) {
      _queueMixerAction(_commitMute(engine!, track, id, value, previous));
    }
  }

  Future<void> _commitMute(EngineController engine, TrackModel track, int id,
      bool value, bool previous) async {
    try {
      await engine.muteTrack(id, value);
    } catch (error) {
      if (!mounted) return;
      if (_nativeTrackIds[track.id] == id && track.muted == value) {
        setState(() => track.muted = previous);
      }
      _reportMixerFailure('Track mute', error);
    }
  }

  void _setTrackSolo(TrackModel track, bool value) {
    final id = _nativeTrackIds[track.id];
    final engine = _engine;
    if (_trackOperationPending) return;
    if (id != null && engine == null) {
      _showEngineUnavailable();
      return;
    }
    final previous = track.solo;
    setState(() {
      track.solo = value;
      if (id != null) _markSessionChanged();
    });
    if (id != null) {
      _queueMixerAction(_commitSolo(engine!, track, id, value, previous));
    }
  }

  Future<void> _commitSolo(EngineController engine, TrackModel track, int id,
      bool value, bool previous) async {
    try {
      await engine.soloTrack(id, value);
    } catch (error) {
      if (!mounted) return;
      if (_nativeTrackIds[track.id] == id && track.solo == value) {
        setState(() => track.solo = previous);
      }
      _reportMixerFailure('Track solo', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): () =>
            unawaited(_togglePlay()),
        const SingleActivator(LogicalKeyboardKey.keyR): () =>
            unawaited(_toggleRecording()),
        const SingleActivator(LogicalKeyboardKey.home): () =>
            unawaited(_goToStart()),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            unawaited(_undoClipMove()),
        const SingleActivator(LogicalKeyboardKey.keyZ,
            control: true, shift: true): () => unawaited(_redoClipMove()),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
            unawaited(_undoClipMove()),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            () => unawaited(_redoClipMove()),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
            unawaited(_redoClipMove()),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(_saveSession()),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            unawaited(_saveSession()),
        const SingleActivator(LogicalKeyboardKey.keyS,
            control: true,
            shift: true): () => unawaited(_saveSession(saveAs: true)),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true):
            () => unawaited(_saveSession(saveAs: true)),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
            unawaited(_openSession()),
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): () =>
            unawaited(_openSession()),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            unawaited(_newSession()),
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            unawaited(_newSession()),
        const SingleActivator(LogicalKeyboardKey.keyK): () =>
            _changePerformance(
                _performance.copyWith(metronome: !_performance.metronome)),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 1000;
                _timelineViewportWidth = math.max(
                  1.0,
                  constraints.maxWidth -
                      (compact || !_browserOpen ? 0 : 222) -
                      196,
                );
                return Column(
                  children: [
                    if (_engineError != null)
                      MaterialBanner(
                        content:
                            Text('Native engine unavailable: $_engineError'),
                        actions: [
                          TextButton(
                            onPressed:
                                _initializingEngine || _trackOperationPending
                                    ? null
                                    : () => unawaited(_initializeEngine()),
                            child: const Text('Retry'),
                          )
                        ],
                      ),
                    _MenuBar(
                      onSelected: _handleMenuCommand,
                      sessionTitle: _sessionTitle,
                      sessionDirty: _sessionDirty,
                    ),
                    _TopBar(
                      isPlaying: _telemetry.isPlaying,
                      isRecording: _isRecording,
                      browserOpen: _browserOpen,
                      mixerOpen: _showMixer,
                      onPlay: _togglePlay,
                      onStop: _stop,
                      onRecord: () => unawaited(_toggleRecording()),
                      onBrowser: () =>
                          setState(() => _browserOpen = !_browserOpen),
                      onMixer: () => setState(() => _showMixer = !_showMixer),
                      tempo: _performance.tempo,
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          if (_browserOpen && !compact)
                            SizedBox(
                              width: 222,
                              child: BrowserPanel(
                                category: _browserCategory,
                                onCategoryChanged: (category) =>
                                    setState(() => _browserCategory = category),
                                onPresetSelected: (name) {
                                  setState(() {
                                    _preset = const [
                                      'Soft Focus',
                                      'Pale Blue',
                                      'Slow Bloom',
                                      'Velvet Tape'
                                    ].contains(name)
                                        ? name
                                        : 'Soft Focus';
                                    _showMixer = false;
                                    final preset = PerformanceSettings.presets
                                        .indexOf(name);
                                    if (preset >= 0) {
                                      _changePerformance(_performance.copyWith(
                                          preset: preset,
                                          macros: PerformanceSettings
                                              .presetMacros[preset]));
                                    }
                                  });
                                },
                              ),
                            ),
                          Expanded(
                            child: Column(
                              children: [
                                _TimelineToolbar(
                                  selectedTrack: _selectedTrack?.name ??
                                      'Import audio or play HypnoSynth',
                                  importing: _importingAudio,
                                  onImport: _initializingEngine ||
                                          _trackOperationPending
                                      ? null
                                      : _importAudio,
                                  zoom: _zoom,
                                  onZoomChanged: (value) =>
                                      setState(() => _zoom = value),
                                  snapToBeat: _snapToBeat,
                                  onSnapChanged: (value) =>
                                      setState(() => _snapToBeat = value),
                                  browserOpen: _browserOpen,
                                  onBrowser: () => setState(
                                      () => _browserOpen = !_browserOpen),
                                ),
                                Expanded(
                                  child: TimelineView(
                                    tracks: _tracks,
                                    selectedTrackId: _selectedTrackId,
                                    selectedClipId: _selectedClipId,
                                    zoom: _zoom,
                                    playheadSeconds: _telemetry.playheadSeconds,
                                    tempo: _performance.tempo.round(),
                                    onTrackSelected: _selectTrack,
                                    onClipSelected: _selectClip,
                                    onClipMoved: _moveClip,
                                    onClipMoveStarted: _beginClipMove,
                                    onClipMoveFinished: _finishClipMove,
                                    onMuteChanged: _setTrackMute,
                                    onSoloChanged: _setTrackSolo,
                                    onVolumeChanged: _setTrackVolume,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_showMixer)
                      HypnoSynthPanel(
                        settings: _performance,
                        enabled: _engine is PerformanceEngine &&
                            !_trackOperationPending &&
                            !_initializingEngine,
                        onSettings: _changePerformance,
                        onNote: (note, down) => unawaited(
                            _sendSynth(down ? 0 : 1, note, down ? 0.8 : 0)),
                        onPanic: () => unawaited(_sendSynth(4, 0, 0)),
                        onAudition: () => unawaited(_auditionSynth()),
                        onMixer: () => setState(() => _showMixer = true),
                      )
                    else
                      InstrumentDock(
                        isMixer: _showMixer,
                        onTabChanged: (value) =>
                            setState(() => _showMixer = value),
                        preset: const [
                          'Soft Focus',
                          'Pale Blue',
                          'Slow Bloom',
                          'Velvet Tape'
                        ].contains(_preset)
                            ? _preset
                            : 'Soft Focus',
                        onPresetChanged: (value) {
                          if (value != null) setState(() => _preset = value);
                        },
                        knobValues: _knobValues,
                        onKnobChanged: (name, value) =>
                            setState(() => _knobValues[name] = value),
                        tracks: _tracks,
                        onVolumeChanged: _setTrackVolume,
                        onPanChanged: _setTrackPan,
                        onMuteChanged: _setTrackMute,
                        onSoloChanged: _setTrackSolo,
                        peakLeft: _telemetry.peakLeft,
                        peakRight: _telemetry.peakRight,
                      ),
                    _StatusBar(
                      engineConnected: _engine != null && _engineError == null,
                      isPlaying: _telemetry.isPlaying,
                      engineError: _engineError,
                      loadedTrackCount: _nativeTrackIds.length,
                      outputDeviceName: _selectedOutputDeviceName,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ClipMoveEdit {
  const _ClipMoveEdit({
    required this.trackId,
    required this.clipId,
    required this.beforeSeconds,
    required this.afterSeconds,
  });

  final String trackId;
  final String clipId;
  final double beforeSeconds;
  final double afterSeconds;
}

class _MenuAction {
  const _MenuAction(this.id, this.label, [this.shortcut]);

  final String id;
  final String label;
  final String? shortcut;
}

class _MenuBar extends StatelessWidget {
  const _MenuBar({
    required this.onSelected,
    required this.sessionTitle,
    required this.sessionDirty,
  });

  final ValueChanged<_MenuAction> onSelected;
  final String sessionTitle;
  final bool sessionDirty;

  static const Map<String, List<_MenuAction>> _menus = {
    'File': [
      _MenuAction('file.new', 'New Session', 'Ctrl+N'),
      _MenuAction('file.open', 'Open Session…', 'Ctrl+O'),
      _MenuAction('file.save', 'Save Session', 'Ctrl+S'),
      _MenuAction('file.saveAs', 'Save Session As…'),
      _MenuAction('file.export', 'Export Mixdown…', 'Ctrl+Alt+E'),
    ],
    'Edit': [
      _MenuAction('edit.undo', 'Undo Clip Move', 'Ctrl+Z'),
      _MenuAction('edit.redo', 'Redo Clip Move', 'Ctrl+Shift+Z'),
      _MenuAction('edit.cut', 'Cut', 'Ctrl+X'),
      _MenuAction('edit.copy', 'Copy', 'Ctrl+C'),
      _MenuAction('edit.paste', 'Paste', 'Ctrl+V'),
      _MenuAction('edit.duplicate', 'Duplicate', 'Ctrl+D'),
    ],
    'Track': [
      _MenuAction('track.addAudio', 'Add Audio Track'),
      _MenuAction('track.addInstrument', 'Add Instrument Track'),
      _MenuAction('track.addBus', 'Add Bus'),
      _MenuAction('track.rename', 'Rename Selected Track'),
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
    'Audio': [
      _MenuAction('audio.output', 'Choose Output Device…'),
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
        border:
            Border(bottom: BorderSide(color: AetherColors.raised, width: 0.7)),
      ),
      child: Row(
        children: [
          Container(
            width: 21,
            height: 21,
            decoration: BoxDecoration(
              color: AetherColors.sage.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
              border:
                  Border.all(color: AetherColors.sage.withValues(alpha: 0.42)),
            ),
            child: const Icon(Icons.graphic_eq,
                color: AetherColors.sage, size: 14),
          ),
          const SizedBox(width: 7),
          const Text(
            'Aetherband',
            style: TextStyle(
                color: AetherColors.paper,
                fontSize: 11,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 13),
          Container(width: 1, height: 17, color: AetherColors.raised),
          const SizedBox(width: 4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
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
                                  style: const TextStyle(
                                      color: AetherColors.paper, fontSize: 12),
                                ),
                              ),
                              if (action.shortcut != null)
                                Text(
                                  action.shortcut!,
                                  style: const TextStyle(
                                      color: AetherColors.secondaryText,
                                      fontSize: 10),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 6),
                      child: Text(
                        menu.key,
                        style: const TextStyle(
                            color: AetherColors.secondaryText, fontSize: 11),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          const Icon(Icons.circle, size: 6, color: AetherColors.magenta),
          const SizedBox(width: 7),
          Text(sessionDirty ? '$sessionTitle *' : sessionTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AetherColors.paper, fontSize: 11)),
          const SizedBox(width: 11),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isPlaying,
    required this.tempo,
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
  final double tempo;
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
          _TransportButton(
              icon: Icons.stop_rounded,
              tooltip: 'Stop transport',
              onTap: onStop),
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
            tooltip:
                isRecording ? 'Stop recording' : 'Record from Windows input',
            onTap: onRecord,
            color:
                isRecording ? AetherColors.magenta : AetherColors.secondaryText,
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
                Text('001 : 01 : 000',
                    style: TextStyle(
                        color: AetherColors.paper,
                        fontSize: 11,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _ValuePlate(label: 'TEMPO', value: tempo.toStringAsFixed(1)),
          const SizedBox(width: 6),
          const _ValuePlate(label: 'METER', value: '4/4', width: 61),
          const Spacer(),
          Text(
            'UI PREVIEW',
            style: TextStyle(
                color: AetherColors.secondaryText.withValues(alpha: 0.78),
                fontSize: 9,
                letterSpacing: 0.8),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: browserOpen ? 'Hide browser' : 'Show browser',
            onPressed: onBrowser,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.view_sidebar_outlined,
                size: 18,
                color: browserOpen
                    ? AetherColors.sage
                    : AetherColors.secondaryText),
          ),
          IconButton(
            tooltip: mixerOpen ? 'Hide mixer' : 'Show mixer',
            onPressed: onMixer,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.equalizer,
                size: 18,
                color: mixerOpen
                    ? AetherColors.magenta
                    : AetherColors.secondaryText),
          ),
          const SizedBox(width: 3),
          const Icon(Icons.settings_outlined,
              size: 17, color: AetherColors.secondaryText),
        ],
      ),
    );
  }
}

class _ValuePlate extends StatelessWidget {
  const _ValuePlate(
      {required this.label, required this.value, this.width = 72});

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
          Text(label,
              style: const TextStyle(
                  color: AetherColors.secondaryText,
                  fontSize: 8,
                  letterSpacing: 0.6)),
          const SizedBox(height: 1),
          Text(value,
              style: const TextStyle(
                  color: AetherColors.paper,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
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
          color: primary
              ? AetherColors.sage.withValues(alpha: 0.15)
              : AetherColors.panel,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: onTap,
            child: Icon(icon,
                size: 19,
                color: color ??
                    (primary ? AetherColors.sage : AetherColors.paper)),
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
    required this.snapToBeat,
    required this.onSnapChanged,
    required this.browserOpen,
    required this.onBrowser,
    required this.onImport,
    required this.importing,
  });

  final String selectedTrack;
  final double zoom;
  final ValueChanged<double> onZoomChanged;
  final bool snapToBeat;
  final ValueChanged<bool> onSnapChanged;
  final bool browserOpen;
  final VoidCallback onBrowser;
  final VoidCallback? onImport;
  final bool importing;

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
          Tooltip(
            message: 'Import audio (rewinds transport)',
            child: TextButton.icon(
              onPressed: onImport,
              icon: importing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.audio_file_outlined, size: 16),
              label: Text(importing ? 'Importing…' : 'Import audio'),
            ),
          ),
          const SizedBox(width: 6),
          const Text('ARRANGEMENT',
              style: TextStyle(
                  color: AetherColors.paper,
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          Container(width: 1, height: 20, color: AetherColors.raised),
          const SizedBox(width: 12),
          IconButton(
            tooltip: snapToBeat ? 'Snap to beats (on)' : 'Snap to beats (off)',
            onPressed: () => onSnapChanged(!snapToBeat),
            visualDensity: VisualDensity.compact,
            color: snapToBeat ? AetherColors.sage : AetherColors.secondaryText,
            icon: const Icon(Icons.grid_on, size: 16),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.layers_outlined, size: 15, color: AetherColors.sage),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Selected: $selectedTrack',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AetherColors.secondaryText, fontSize: 11)),
          ),
          const Icon(Icons.zoom_out,
              size: 15, color: AetherColors.secondaryText),
          SizedBox(
              width: 120,
              child: Slider(
                  key: const ValueKey('timeline-zoom'),
                  value: zoom,
                  min: 0.2,
                  max: 1.5,
                  onChanged: onZoomChanged)),
          const Icon(Icons.zoom_in,
              size: 15, color: AetherColors.secondaryText),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
                color: AetherColors.background,
                borderRadius: BorderRadius.circular(4)),
            child: Text('${(zoom * 100).round()}%',
                style: const TextStyle(
                    color: AetherColors.secondaryText, fontSize: 10)),
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
    required this.loadedTrackCount,
    required this.outputDeviceName,
  });

  final bool engineConnected;
  final bool isPlaying;
  final Object? engineError;
  final int loadedTrackCount;
  final String? outputDeviceName;

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
            style: TextStyle(
                color: AetherColors.secondaryText,
                fontSize: 8,
                letterSpacing: 0.6),
          ),
          const Spacer(),
          Text(
            engineConnected
                ? (loadedTrackCount > 0
                    ? '$loadedTrackCount AUDIO ${loadedTrackCount == 1 ? 'TRACK' : 'TRACKS'} LOADED · ${isPlaying ? 'PLAYING' : 'READY'}'
                    : 'EMPTY SESSION · ${isPlaying ? 'PLAYING' : 'READY'}')
                : 'ENGINE UNAVAILABLE',
            style: const TextStyle(
                color: AetherColors.secondaryText,
                fontSize: 8,
                letterSpacing: 0.4),
          ),
          if (outputDeviceName != null) ...[
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                'OUTPUT · $outputDeviceName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AetherColors.sage, fontSize: 8, letterSpacing: 0.4),
              ),
            ),
          ],
          if (engineError != null) ...[
            const SizedBox(width: 8),
            const Icon(Icons.warning_amber_rounded,
                color: AetherColors.magenta, size: 11),
          ],
          const SizedBox(width: 8),
          const Text(
            'WINDOWS ONLY',
            style: TextStyle(
                color: AetherColors.sage, fontSize: 8, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}
