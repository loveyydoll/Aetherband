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
  final Map<String, int> _nativeRegionIds = <String, int>{};
  final Map<String, int> _nativeSequenceRegionIds = <String, int>{};
  final Map<String, String> _nativeTrackSources = <String, String>{};
  SavedAudioTrack? _copiedAudioTrack;
  ClipModel? _copiedSequenceRegion;
  final Map<String, Timer> _clipPositionTimers = <String, Timer>{};
  final Map<String, double> _confirmedClipStarts = <String, double>{};
  final Map<String, double> _clipMoveStarts = <String, double>{};
  final List<Object> _undoHistory = <Object>[];
  final List<Object> _redoHistory = <Object>[];
  bool _historyOperationPending = false;
  bool _positionMoveDeniedShown = false;
  final AudioSessionStore _sessionStore = const AudioSessionStore();
  final Set<Future<void>> _mixerActions = <Future<void>>{};
  String _sessionTitle = 'Untitled Session';
  String? _sessionPath;
  bool _sessionDirty = false;
  int _sessionRevision = 0;
  int _nextPersistentTrackSerial = 0;
  int _nextSequenceRegionId = 1;
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

  int _createSequenceRegionId() {
    for (var attempt = 0;
        attempt <= _nativeSequenceRegionIds.length;
        attempt++) {
      final candidate = _nextSequenceRegionId;
      _nextSequenceRegionId = candidate == 0xffffffff ? 1 : candidate + 1;
      if (candidate > 0 &&
          !_nativeSequenceRegionIds.values.contains(candidate)) {
        return candidate;
      }
    }
    throw StateError('No HypnoSynth pattern region IDs are available.');
  }

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
        _nativeRegionIds.clear();
        _nativeTrackSources.clear();
        _clipMoveStarts.clear();
        _undoHistory.clear();
        _redoHistory.clear();
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
    if (_trackOperationPending ||
        _historyOperationPending ||
        _initializingEngine) {
      return;
    }
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

  Future<void> _seekToSeconds(double seconds) async {
    if (_isRecording) {
      _showRecordingSessionGuard();
      return;
    }
    final engine = _engine;
    if (engine == null || engine is! TransportSeekEngine) {
      _showFeatureUnavailable('Transport seeking');
      return;
    }
    try {
      await (engine as TransportSeekEngine).seekSeconds(seconds);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not seek transport: $error')),
        );
      }
    }
  }

  Future<void> _seekPreviousBar() async {
    final secondsPerBar = 240 / _performance.tempo;
    final currentBar = (_telemetry.playheadSeconds / secondsPerBar).ceil() - 1;
    await _seekToSeconds(math.max(0, currentBar) * secondsPerBar);
  }

  Future<void> _seekNextBar() async {
    final secondsPerBar = 240 / _performance.tempo;
    final nextBar = (_telemetry.playheadSeconds / secondsPerBar).floor() + 1;
    await _seekToSeconds(nextBar * secondsPerBar);
  }

  Future<void> _seekToEnd() async {
    final endSeconds = _tracks.expand((track) => track.clips).fold<double>(
          0,
          (end, clip) => math.max(
            end,
            clip.timelineLeft(_performance.tempo.round()) +
                clip.timelineWidth(_performance.tempo.round()),
          ),
        );
    await _seekToSeconds(endSeconds);
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
    if (peaks != null && clip.sourceDurationSeconds != null) {
      peaks = _sliceWaveform(
        peaks,
        clip.sourceDurationSeconds!,
        clip.sourceStartSeconds,
        clip.durationSeconds ?? clip.sourceDurationSeconds!,
      );
    }
    setState(() {
      clip.waveformPeaks = peaks;
      clip.waveformLoaded = true;
    });
  }

  List<double> _sliceWaveform(List<double> peaks, double sourceDuration,
      double sourceStart, double duration) {
    if (peaks.isEmpty || sourceDuration <= 0 || duration <= 0) return peaks;
    final first = (sourceStart / sourceDuration * peaks.length)
        .floor()
        .clamp(0, peaks.length - 1);
    final last = ((sourceStart + duration) / sourceDuration * peaks.length)
        .ceil()
        .clamp(first + 1, peaks.length);
    return peaks.sublist(first, last);
  }

  int? _nativeIdForClip(ClipModel clip) => _nativeRegionIds[clip.id];

  List<int> _nativeIdsForTrack(TrackModel track) => track.clips
      .map(_nativeIdForClip)
      .whereType<int>()
      .toSet()
      .toList(growable: false);

  Future<void> _splitSelectedRegionAtPlayhead() async {
    final track = _selectedTrack;
    final clip =
        track?.clips.where((item) => item.id == _selectedClipId).firstOrNull;
    final engine = _engine;
    if (track == null || clip == null || clip.isDemo) {
      _showFeatureUnavailable('Splitting demo or unselected clips');
      return;
    }
    if (_trackOperationPending || _initializingEngine) return;
    if (_telemetry.isPlaying || _isRecording) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Stop playback and recording before splitting a clip.'),
      ));
      return;
    }
    if (engine == null || engine is! AudioRegionEngine) {
      _showFeatureUnavailable('Audio region editing');
      return;
    }
    final duration = clip.durationSeconds;
    final fullDuration = clip.sourceDurationSeconds;
    final start = _telemetry.playheadSeconds;
    final local = start - clip.startSeconds;
    if (duration == null ||
        fullDuration == null ||
        local < 0.02 ||
        duration - local < 0.02 ||
        clip.sourceStartSeconds + duration > fullDuration + 0.02) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Place the playhead inside the clip, away from its edges.'),
      ));
      return;
    }
    final nativeIds = _nativeIdsForTrack(track);
    final originalId = _nativeIdForClip(clip);
    if (originalId == null || nativeIds.length != track.clips.length) {
      _showEngineUnavailable();
      return;
    }
    setState(() => _trackOperationPending = true);
    int? createdId;
    var leftChanged = false;
    try {
      if (await engine.getTrackCount() >= AudioSessionDocument.maxTracks) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('This session has reached its audio region limit.'),
          ));
        }
        return;
      }
      if (!mounted) return;
      final loaded = await engine.loadTrack(_nativeTrackSources[track.id]!);
      createdId = loaded.id;
      await engine.setTrackVolume(loaded.id, track.volume);
      await engine.setTrackPan(loaded.id, track.pan);
      await engine.muteTrack(loaded.id, track.muted);
      await engine.soloTrack(loaded.id, track.solo);
      final splitEngine = engine as AudioRegionEngine;
      final rightDuration = duration - local;
      await splitEngine.setTrackRegionSeconds(
          loaded.id, clip.sourceStartSeconds + local, rightDuration);
      await engine.setTrackStartSeconds(loaded.id, start);
      await splitEngine.setTrackRegionSeconds(
          originalId, clip.sourceStartSeconds, local);
      leftChanged = true;

      final originalPeaks = clip.waveformPeaks == null
          ? null
          : List<double>.of(clip.waveformPeaks!);
      final rightPeaks = clip.waveformPeaks == null
          ? null
          : _sliceWaveform(clip.waveformPeaks!, duration, local, rightDuration);
      final leftPeaks = clip.waveformPeaks == null
          ? null
          : _sliceWaveform(clip.waveformPeaks!, duration, 0, local);
      final right = ClipModel(
        id: '${track.id}-region-${_createPersistentTrackId()}',
        title: clip.title,
        start: 0,
        width: 0,
        color: clip.color,
        isDemo: false,
        durationSeconds: rightDuration,
        sourceDurationSeconds: fullDuration,
        sourceStartSeconds: clip.sourceStartSeconds + local,
        startSeconds: start,
        waveformPeaks: rightPeaks,
        waveformLoaded: clip.waveformLoaded,
      );
      if (!mounted) return;
      setState(() {
        clip.durationSeconds = local;
        clip.waveformPeaks = leftPeaks;
        track.clips.insert(track.clips.indexOf(clip) + 1, right);
        _nativeRegionIds[right.id] = loaded.id;
        _confirmedClipStarts[right.id] = right.startSeconds;
        _selectedClipId = right.id;
        _markSessionChanged();
      });
      _pushHistory(_RegionSplitEdit(
        trackId: track.id,
        originalClip: clip,
        rightClip: right,
        originalDuration: duration,
        originalWaveform: originalPeaks,
        splitWaveform: leftPeaks,
        rightNativeId: loaded.id,
      ));
      createdId = null;
    } catch (error) {
      if (leftChanged) {
        try {
          await (engine as AudioRegionEngine).setTrackRegionSeconds(
              originalId, clip.sourceStartSeconds, duration);
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Split failed: $error')),
        );
      }
    } finally {
      if (createdId != null) {
        try {
          await engine.removeTrack(createdId);
        } catch (_) {}
      }
      if (mounted) setState(() => _trackOperationPending = false);
    }
  }

  Future<void> _joinSelectedRegions() async {
    final track = _selectedTrack;
    final selected =
        track?.clips.where((item) => item.id == _selectedClipId).firstOrNull;
    final engine = _engine;
    if (track == null || selected == null || selected.isDemo) {
      _showFeatureUnavailable('Joining unselected or demo regions');
      return;
    }
    if (_trackOperationPending ||
        _historyOperationPending ||
        _initializingEngine) {
      return;
    }
    if (_telemetry.isPlaying || _isRecording) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Stop playback and recording before joining regions.'),
      ));
      return;
    }
    if (engine == null || engine is! AudioRegionEngine) {
      _showFeatureUnavailable('Audio region editing');
      return;
    }
    final selectedIndex = track.clips.indexOf(selected);
    final previous = selectedIndex > 0 ? track.clips[selectedIndex - 1] : null;
    final next = selectedIndex + 1 < track.clips.length
        ? track.clips[selectedIndex + 1]
        : null;
    final pair = _regionsAreContiguous(previous, selected)
        ? (previous!, selected)
        : _regionsAreContiguous(selected, next)
            ? (selected, next!)
            : null;
    if (pair == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Select one of two adjacent regions from the same source to join them.'),
      ));
      return;
    }
    final (left, right) = pair;
    final leftNativeId = _nativeIdForClip(left);
    final rightNativeId = _nativeIdForClip(right);
    final leftDuration = left.durationSeconds;
    final rightDuration = right.durationSeconds;
    if (leftNativeId == null ||
        rightNativeId == null ||
        leftDuration == null ||
        rightDuration == null) {
      _showEngineUnavailable();
      return;
    }
    final joinedDuration = leftDuration + rightDuration;
    final joinedWaveform =
        left.waveformPeaks == null || right.waveformPeaks == null
            ? null
            : <double>[...left.waveformPeaks!, ...right.waveformPeaks!];
    final leftWaveform = left.waveformPeaks == null
        ? null
        : List<double>.of(left.waveformPeaks!);
    setState(() => _trackOperationPending = true);
    try {
      final regionEngine = engine as AudioRegionEngine;
      await regionEngine.setTrackRegionSeconds(
        leftNativeId,
        left.sourceStartSeconds,
        joinedDuration,
      );
      try {
        await engine.removeTrack(rightNativeId);
      } catch (_) {
        await regionEngine.setTrackRegionSeconds(
          leftNativeId,
          left.sourceStartSeconds,
          leftDuration,
        );
        rethrow;
      }
      setState(() {
        left.durationSeconds = joinedDuration;
        left.waveformPeaks = joinedWaveform;
        track.clips.remove(right);
        _nativeRegionIds.remove(right.id);
        _confirmedClipStarts.remove(right.id);
        _selectedClipId = left.id;
        _markSessionChanged();
      });
      _pushHistory(_RegionSplitEdit(
        trackId: track.id,
        originalClip: left,
        rightClip: right,
        originalDuration: joinedDuration,
        originalWaveform:
            joinedWaveform == null ? null : List<double>.of(joinedWaveform),
        splitWaveform: leftWaveform,
        rightNativeId: rightNativeId,
        wasJoined: true,
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not join audio regions: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _trackOperationPending = false);
    }
  }

  bool _regionsAreContiguous(ClipModel? left, ClipModel? right) {
    if (left == null || right == null || left.isDemo || right.isDemo) {
      return false;
    }
    final leftDuration = left.durationSeconds;
    final rightDuration = right.durationSeconds;
    final sameSource = left.sourceDurationSeconds != null &&
        left.sourceDurationSeconds == right.sourceDurationSeconds;
    return sameSource &&
        leftDuration != null &&
        rightDuration != null &&
        (left.startSeconds + leftDuration - right.startSeconds).abs() < 0.02 &&
        (left.sourceStartSeconds + leftDuration - right.sourceStartSeconds)
                .abs() <
            0.02;
  }

  Future<void> _trimSelectedRegionAtPlayhead({required bool trimStart}) async {
    final track = _selectedTrack;
    final clip =
        track?.clips.where((item) => item.id == _selectedClipId).firstOrNull;
    final engine = _engine;
    if (track == null || clip == null || clip.isDemo) {
      _showFeatureUnavailable('Trimming unselected or demo regions');
      return;
    }
    if (_trackOperationPending ||
        _historyOperationPending ||
        _initializingEngine) {
      return;
    }
    if (_telemetry.isPlaying || _isRecording) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Stop playback and recording before trimming a region.'),
      ));
      return;
    }
    if (engine == null || engine is! AudioRegionEngine) {
      _showFeatureUnavailable('Audio region editing');
      return;
    }
    final nativeId = _nativeIdForClip(clip);
    final duration = clip.durationSeconds;
    final fullDuration = clip.sourceDurationSeconds;
    final local = _telemetry.playheadSeconds - clip.startSeconds;
    if (nativeId == null || duration == null || fullDuration == null) {
      _showEngineUnavailable();
      return;
    }
    if (local < 0.02 || duration - local < 0.02) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Place the playhead inside the region, away from its edges.'),
      ));
      return;
    }
    final beforeSourceStart = clip.sourceStartSeconds;
    final beforeDuration = duration;
    final beforeStart = clip.startSeconds;
    final beforeWaveform = clip.waveformPeaks == null
        ? null
        : List<double>.of(clip.waveformPeaks!);
    final afterSourceStart =
        trimStart ? clip.sourceStartSeconds + local : clip.sourceStartSeconds;
    final afterDuration = trimStart ? duration - local : local;
    final afterStart =
        trimStart ? _telemetry.playheadSeconds : clip.startSeconds;
    final afterWaveform = clip.waveformPeaks == null
        ? null
        : _sliceWaveform(clip.waveformPeaks!, duration, trimStart ? local : 0,
            afterDuration);
    setState(() => _trackOperationPending = true);
    try {
      final regionEngine = engine as AudioRegionEngine;
      await regionEngine.setTrackRegionSeconds(
          nativeId, afterSourceStart, afterDuration);
      try {
        await engine.setTrackStartSeconds(nativeId, afterStart);
      } catch (_) {
        await regionEngine.setTrackRegionSeconds(
            nativeId, beforeSourceStart, beforeDuration);
        await engine.setTrackStartSeconds(nativeId, beforeStart);
        rethrow;
      }
      setState(() {
        clip.sourceStartSeconds = afterSourceStart;
        clip.durationSeconds = afterDuration;
        clip.startSeconds = afterStart;
        clip.waveformPeaks = afterWaveform;
        _confirmedClipStarts[clip.id] = afterStart;
        _markSessionChanged();
      });
      _pushHistory(_RegionTrimEdit(
        trackId: track.id,
        clip: clip,
        beforeSourceStart: beforeSourceStart,
        beforeDuration: beforeDuration,
        beforeStart: beforeStart,
        beforeWaveform: beforeWaveform,
        afterSourceStart: afterSourceStart,
        afterDuration: afterDuration,
        afterStart: afterStart,
        afterWaveform:
            afterWaveform == null ? null : List<double>.of(afterWaveform),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not trim audio region: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _trackOperationPending = false);
    }
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
        _nativeRegionIds[clip.id] = nativeId;
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
      _nativeRegionIds[clip.id] = loaded.id;
      _nativeTrackSources[id] = path;
      _showMixer = true;
      _markSessionChanged();
      _tracks.add(track);
      _selectedTrackId = id;
      _selectedClipId = '$id-clip';
    });
    unawaited(_loadClipWaveform(track, clip, path));
  }

  Future<void> _removeSelectedPatternRegion() async {
    final clip = _tracks
        .expand((track) => track.clips)
        .where((clip) => clip.id == _selectedClipId && clip.isSequenceRegion)
        .firstOrNull;
    final regionId = clip == null ? null : _nativeSequenceRegionIds[clip.id];
    final engine = _engine;
    if (clip == null || regionId == null || engine is! SequenceRegionEngine) {
      return;
    }
    final track =
        _tracks.where((track) => track.clips.contains(clip)).firstOrNull;
    if (track == null) return;
    try {
      await (engine as SequenceRegionEngine).removeSequenceRegion(regionId);
      if (!mounted) return;
      setState(() {
        track.clips.remove(clip);
        _nativeSequenceRegionIds.remove(clip.id);
        _confirmedClipStarts.remove(clip.id);
        _selectedClipId = null;
        _markSessionChanged();
        _pushHistory(_SequenceRegionEdit(
          trackId: track.id,
          clip: clip,
          regionId: regionId,
          presentAfterEdit: false,
        ));
      });
    } catch (error) {
      if (mounted) _reportMixerFailure('Remove HypnoSynth pattern', error);
    }
  }

  Future<void> _removeSelectedTrack() async {
    if (_trackOperationPending || _initializingEngine) return;
    final engine = _engine;
    final selectedId = _selectedTrackId;
    final selected =
        _tracks.where((track) => track.id == selectedId).firstOrNull;
    final nativeIds = selected == null ? <int>[] : _nativeIdsForTrack(selected);
    if (selected?.kind == 'INSTRUMENT' && nativeIds.isEmpty) {
      if (engine is! PerformanceEngine) {
        _showEngineUnavailable();
        return;
      }
      final performanceEngine = engine as PerformanceEngine;
      setState(() => _trackOperationPending = true);
      try {
        if (selected != null && engine is SequenceRegionEngine) {
          for (final clip
              in selected.clips.where((clip) => clip.isSequenceRegion)) {
            final regionId = _nativeSequenceRegionIds[clip.id];
            if (regionId != null) {
              await (engine as SequenceRegionEngine)
                  .removeSequenceRegion(regionId);
            }
          }
        }
        await performanceEngine.synthEvent(6, 0, 0.8);
        await performanceEngine.synthEvent(7, 0, 0.5);
        await performanceEngine.synthEvent(8, 0, 0.0);
        await performanceEngine.synthEvent(9, 0, 0.0);
        if (!mounted) return;
        setState(() {
          for (final clip in selected?.clips ?? const <ClipModel>[]) {
            _nativeSequenceRegionIds.remove(clip.id);
          }
          _undoHistory
              .removeWhere((edit) => _historyTrackId(edit) == selectedId);
          _redoHistory
              .removeWhere((edit) => _historyTrackId(edit) == selectedId);
          _tracks.removeWhere((track) => track.id == selectedId);
          _selectedTrackId = _tracks.isEmpty ? '' : _tracks.first.id;
          _selectedClipId = null;
          _markSessionChanged();
        });
      } catch (error) {
        if (mounted) _reportMixerFailure('HypnoSynth track removal', error);
      } finally {
        if (mounted) setState(() => _trackOperationPending = false);
      }
      return;
    }
    if (engine == null || nativeIds.isEmpty) {
      _showFeatureUnavailable('Removing demo tracks');
      return;
    }
    setState(() => _trackOperationPending = true);
    final removedNativeIds = <int>[];
    try {
      for (final nativeId in nativeIds) {
        await engine.removeTrack(nativeId);
        removedNativeIds.add(nativeId);
      }
      if (!mounted) return;
      setState(() {
        final removedTrack =
            _tracks.where((track) => track.id == selectedId).firstOrNull;
        _tracks.removeWhere((track) => track.id == selectedId);
        _nativeTrackIds.remove(selectedId);
        for (final clip in removedTrack?.clips ?? const <ClipModel>[]) {
          _nativeRegionIds.remove(clip.id);
        }
        _nativeTrackSources.remove(selectedId);
        if (removedTrack != null) {
          for (final clip in removedTrack.clips) {
            _clipPositionTimers.remove(clip.id)?.cancel();
            _confirmedClipStarts.remove(clip.id);
            _clipMoveStarts.remove(clip.id);
          }
        }
        _undoHistory.removeWhere((edit) => _historyTrackId(edit) == selectedId);
        _redoHistory.removeWhere((edit) => _historyTrackId(edit) == selectedId);
        _markSessionChanged();
        if (_selectedTrackId == selectedId) {
          _selectedTrackId = _tracks.isEmpty ? '' : _tracks.first.id;
          _selectedClipId = null;
        }
      });
    } catch (error) {
      if (mounted) {
        if (removedNativeIds.isNotEmpty) {
          setState(() {
            final track =
                _tracks.where((item) => item.id == selectedId).firstOrNull;
            if (track != null) {
              final removedClips = track.clips
                  .where((clip) =>
                      removedNativeIds.contains(_nativeRegionIds[clip.id]))
                  .toList();
              for (final clip in removedClips) {
                track.clips.remove(clip);
                _nativeRegionIds.remove(clip.id);
                _confirmedClipStarts.remove(clip.id);
                _clipPositionTimers.remove(clip.id)?.cancel();
              }
              final remaining = _nativeIdsForTrack(track);
              if (remaining.isEmpty) {
                _tracks.remove(track);
                _nativeTrackIds.remove(selectedId);
                _nativeTrackSources.remove(selectedId);
                _selectedTrackId = _tracks.isEmpty ? '' : _tracks.first.id;
                _selectedClipId = null;
              } else {
                _nativeTrackIds[selectedId] = remaining.first;
              }
              _markSessionChanged();
            }
          });
        }
        final message = removedNativeIds.isEmpty
            ? 'Track removal failed: $error'
            : 'Track removal was incomplete after some regions were removed: $error';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _trackOperationPending = false);
    }
  }

  Future<void> _duplicateSelectedTrack() async {
    final selectedPattern = _selectedPatternRegion;
    if (selectedPattern != null) {
      await _copyOrDuplicateSequenceRegion(selectedPattern,
          startSeconds: selectedPattern.startSeconds +
              (selectedPattern.durationSeconds ?? 0));
      return;
    }
    final selected = _selectedTrack;
    final source = selected == null ? null : _nativeTrackSources[selected.id];
    if (selected == null || source == null) {
      _showFeatureUnavailable('Duplicating demo or instrument tracks');
      return;
    }
    await _duplicateAudioTrack(selected, source);
  }

  Future<void> _duplicateAudioTrack(
    TrackModel selected,
    String source, {
    double? startSeconds,
  }) async {
    if (_trackOperationPending || _initializingEngine) return;
    final engine = _engine;
    final clips = List<ClipModel>.of(selected.clips);
    if (engine == null) {
      _showEngineUnavailable();
      return;
    }
    if (clips.isEmpty) return;
    final sourceStart = clips
        .map((clip) => clip.startSeconds)
        .reduce((left, right) => math.min(left, right));
    final targetStart = startSeconds ?? sourceStart;

    setState(() => _trackOperationPending = true);
    final uncommittedNativeIds = <int>[];
    var adopted = false;
    try {
      if (await engine.getTrackCount() + clips.length >
          AudioSessionDocument.maxTracks) {
        throw StateError(
            'A session can contain at most ${AudioSessionDocument.maxTracks} audio regions.');
      }
      final id = _createPersistentTrackId();
      final suffix = ' copy';
      final name = selected.name.length + suffix.length <= 120
          ? '${selected.name}$suffix'
          : '${selected.name.substring(0, 120 - suffix.length)}$suffix';
      final duplicateClips = <ClipModel>[];
      final duplicateNativeIds = <String, int>{};
      for (var index = 0; index < clips.length; index++) {
        final sourceClip = clips[index];
        final loaded = await engine.loadTrack(source);
        uncommittedNativeIds.add(loaded.id);
        await engine.setTrackVolume(loaded.id, selected.volume);
        await engine.setTrackPan(loaded.id, selected.pan);
        await engine.muteTrack(loaded.id, selected.muted);
        await engine.soloTrack(loaded.id, selected.solo);
        final duration = sourceClip.durationSeconds ?? loaded.durationSeconds;
        final regionEngine = engine;
        final needsRegion = sourceClip.sourceStartSeconds > 0 ||
            (duration != null &&
                loaded.durationSeconds != null &&
                duration < loaded.durationSeconds! - 0.00001);
        if (needsRegion) {
          if (regionEngine is! AudioRegionEngine || duration == null) {
            throw StateError('This engine cannot duplicate trimmed regions.');
          }
          await (regionEngine as AudioRegionEngine).setTrackRegionSeconds(
              loaded.id, sourceClip.sourceStartSeconds, duration);
        }
        final clipId =
            clips.length == 1 ? '$id-clip' : '$id-region-${index + 1}';
        final duplicateClip = ClipModel(
          id: clipId,
          title: sourceClip.title,
          start: 0,
          width: 0,
          color: selected.color,
          isDemo: false,
          durationSeconds: duration,
          sourceDurationSeconds: loaded.durationSeconds,
          sourceStartSeconds: sourceClip.sourceStartSeconds,
          startSeconds: targetStart + sourceClip.startSeconds - sourceStart,
          waveformPeaks: sourceClip.waveformPeaks == null
              ? null
              : List<double>.of(sourceClip.waveformPeaks!),
          waveformLoaded: sourceClip.waveformLoaded,
        );
        await engine.setTrackStartSeconds(
            loaded.id, duplicateClip.startSeconds);
        duplicateClips.add(duplicateClip);
        duplicateNativeIds[clipId] = loaded.id;
      }
      final duplicate = TrackModel(
        id: id,
        name: name,
        kind: selected.kind,
        color: selected.color,
        clips: duplicateClips,
        muted: selected.muted,
        solo: selected.solo,
        volume: selected.volume,
        pan: selected.pan,
      );
      if (!mounted) return;
      setState(() {
        _nativeTrackIds[id] = duplicateNativeIds.values.first;
        _nativeRegionIds.addAll(duplicateNativeIds);
        for (final clip in duplicateClips) {
          _confirmedClipStarts[clip.id] = clip.startSeconds;
        }
        _nativeTrackSources[id] = source;
        _tracks.add(duplicate);
        _selectedTrackId = id;
        _selectedClipId = duplicateClips.first.id;
        _markSessionChanged();
      });
      adopted = true;
      uncommittedNativeIds.clear();
      for (final clip in duplicateClips) {
        unawaited(_loadClipWaveform(duplicate, clip, source));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Track duplication failed: $error')),
        );
      }
    } finally {
      if (!adopted && uncommittedNativeIds.isNotEmpty) {
        var cleanupFailed = false;
        for (final nativeId in uncommittedNativeIds) {
          try {
            await engine.removeTrack(nativeId);
          } catch (_) {
            cleanupFailed = true;
          }
        }
        if (cleanupFailed) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'The duplicate could not be added, and one or more temporary audio regions could not be removed.'),
            ));
          }
        }
      }
      if (mounted) setState(() => _trackOperationPending = false);
    }
  }

  bool _copySelectedItem() {
    final pattern = _selectedPatternRegion;
    if (pattern != null) {
      _copiedAudioTrack = null;
      _copiedSequenceRegion = ClipModel(
        id: pattern.id,
        title: pattern.title,
        start: pattern.start,
        width: pattern.width,
        color: pattern.color,
        isDemo: false,
        isSequenceRegion: true,
        sequenceNotes: List<int?>.unmodifiable(pattern.sequenceNotes),
        durationSeconds: pattern.durationSeconds,
        startSeconds: pattern.startSeconds,
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Copied HypnoSynth pattern.'),
      ));
      return true;
    }
    final selected = _selectedTrack;
    final source = selected == null ? null : _nativeTrackSources[selected.id];
    if (selected == null || source == null || selected.clips.isEmpty) {
      _showFeatureUnavailable('Copying demo or instrument tracks');
      return false;
    }
    _copiedAudioTrack = SavedAudioTrack(
      id: selected.id,
      name: selected.name,
      sourceUri: File(source).absolute.uri.toString(),
      gain: selected.volume,
      pan: selected.pan,
      muted: selected.muted,
      solo: selected.solo,
      startSeconds: selected.clips.first.startSeconds,
      regions: selected.clips
          .map((clip) => SavedAudioRegion(
                id: clip.id,
                startSeconds: clip.startSeconds,
                sourceStartSeconds: clip.sourceStartSeconds,
                durationSeconds: clip.durationSeconds,
              ))
          .toList(growable: false),
    );
    _copiedSequenceRegion = null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${selected.name}.')),
    );
    return true;
  }

  Future<void> _pasteAudioTrack() async {
    if (_trackOperationPending || _initializingEngine) return;
    final copiedPattern = _copiedSequenceRegion;
    if (copiedPattern != null) {
      await _copyOrDuplicateSequenceRegion(copiedPattern,
          startSeconds: _telemetry.playheadSeconds);
      return;
    }
    final copied = _copiedAudioTrack;
    if (copied == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Copy an audio track before pasting.'),
      ));
      return;
    }
    final clips = copied.effectiveRegions
        .map((region) => ClipModel(
              id: region.id,
              title: copied.name,
              start: 0,
              width: 0,
              color: AetherColors.sage,
              isDemo: false,
              durationSeconds: region.durationSeconds,
              sourceStartSeconds: region.sourceStartSeconds,
              startSeconds: region.startSeconds,
            ))
        .toList(growable: false);
    final sourceTrack = TrackModel(
      id: copied.id,
      name: copied.name,
      kind: 'AUDIO',
      color: AetherColors.sage,
      clips: clips,
      muted: copied.muted,
      solo: copied.solo,
      volume: copied.gain,
      pan: copied.pan,
    );
    await _duplicateAudioTrack(
      sourceTrack,
      copied.sourcePath,
      startSeconds: _telemetry.playheadSeconds,
    );
  }

  ClipModel? get _selectedPatternRegion => _tracks
      .expand((track) => track.clips)
      .where((clip) => clip.id == _selectedClipId && clip.isSequenceRegion)
      .firstOrNull;

  Future<void> _copyOrDuplicateSequenceRegion(ClipModel source,
      {required double startSeconds}) async {
    if (_trackOperationPending || _initializingEngine) return;
    final engine = _engine;
    if (engine is! SequenceRegionEngine) {
      _showFeatureUnavailable('HypnoSynth pattern regions');
      return;
    }
    final sequenceEngine = engine as SequenceRegionEngine;
    var track =
        _tracks.where((value) => value.kind == 'INSTRUMENT').firstOrNull;
    if (track == null) {
      _addInstrumentTrack();
      track = _tracks.where((value) => value.kind == 'INSTRUMENT').firstOrNull;
    }
    if (track == null) return;
    final regionId = _createSequenceRegionId();
    final notes = List<int?>.unmodifiable(source.sequenceNotes);
    final beatSeconds = 60 / _performance.tempo;
    final start = (startSeconds / beatSeconds).round() * beatSeconds;
    final clipId = '${track.id}-pattern-$regionId';
    try {
      await sequenceEngine.setSequenceRegion(regionId, start, notes);
      if (!mounted) {
        await sequenceEngine.removeSequenceRegion(regionId);
        return;
      }
      final clip = ClipModel(
        id: clipId,
        title: source.title,
        start: 0,
        width: 0,
        color: AetherColors.magenta,
        isDemo: false,
        isSequenceRegion: true,
        sequenceNotes: notes,
        durationSeconds: 8 * beatSeconds,
        startSeconds: start,
      );
      setState(() {
        _nativeSequenceRegionIds[clipId] = regionId;
        _confirmedClipStarts[clipId] = start;
        track!.clips.add(clip);
        _selectedTrackId = track.id;
        _selectedClipId = clipId;
        _showMixer = true;
        _markSessionChanged();
        _pushHistory(_SequenceRegionEdit(
          trackId: track.id,
          clip: clip,
          regionId: regionId,
          presentAfterEdit: true,
        ));
      });
    } catch (error) {
      if (mounted) _reportMixerFailure('Copy HypnoSynth pattern', error);
    }
  }

  Future<void> _renameSelectedTrack() async {
    final selected = _selectedTrack;
    if (selected == null ||
        (!_nativeTrackSources.containsKey(selected.id) &&
            selected.kind != 'INSTRUMENT')) {
      _showFeatureUnavailable('Renaming demo tracks');
      return;
    }
    var draft = selected.name;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename track'),
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
        regions: track.clips
            .where((clip) => !clip.isDemo)
            .map((clip) => SavedAudioRegion(
                  id: clip.id,
                  startSeconds: clip.startSeconds,
                  sourceStartSeconds: clip.sourceStartSeconds,
                  durationSeconds: clip.durationSeconds,
                ))
            .toList(growable: false),
      ));
    }
    return AudioSessionDocument(
        title: title,
        tracks: tracks,
        instrumentTracks: _tracks
            .where((track) => track.kind == 'INSTRUMENT')
            .map((track) => SavedInstrumentTrack(
                  id: track.id,
                  name: track.name,
                  gain: track.volume,
                  pan: track.pan,
                  muted: track.muted,
                  solo: track.solo,
                  regions: track.clips
                      .where((clip) => clip.isSequenceRegion)
                      .map((clip) => SavedSequenceRegion(
                            id: _nativeSequenceRegionIds[clip.id] ?? 0,
                            startSeconds: clip.startSeconds,
                            notes: clip.sequenceNotes,
                          ))
                      .toList(growable: false),
                ))
            .toList(growable: false),
        performance: _performance);
  }

  void _addInstrumentTrack() {
    if (_engine is! PerformanceEngine) {
      _showEngineUnavailable();
      return;
    }
    final existing = _tracks.where((track) => track.kind == 'INSTRUMENT');
    if (existing.isNotEmpty) {
      setState(() {
        _selectedTrackId = existing.first.id;
        _selectedClipId = null;
        _showMixer = true;
      });
      return;
    }
    final engine = _engine as PerformanceEngine;
    _queueMixerAction(() async {
      try {
        await engine.synthEvent(6, 0, 0.8);
        await engine.synthEvent(7, 0, 0.5);
        await engine.synthEvent(8, 0, 0.0);
        await engine.synthEvent(9, 0, 0.0);
      } catch (error) {
        if (mounted) _reportMixerFailure('HypnoSynth track setup', error);
      }
    }());
    final id = _createPersistentTrackId();
    setState(() {
      _tracks.add(TrackModel(
        id: id,
        name: 'HypnoSynth',
        kind: 'INSTRUMENT',
        color: AetherColors.magenta,
        volume: 0.8,
        pan: 0.5,
        muted: false,
        solo: false,
        clips: <ClipModel>[],
      ));
      _selectedTrackId = id;
      _selectedClipId = null;
      _showMixer = true;
      _markSessionChanged();
    });
  }

  Future<void> _insertSequenceRegion() async {
    if (_trackOperationPending || _initializingEngine) return;
    final engine = _engine;
    if (engine is! SequenceRegionEngine) {
      _showFeatureUnavailable('HypnoSynth pattern regions');
      return;
    }
    var track =
        _tracks.where((value) => value.kind == 'INSTRUMENT').firstOrNull;
    if (track == null) {
      _addInstrumentTrack();
      track = _tracks.where((value) => value.kind == 'INSTRUMENT').firstOrNull;
    }
    if (track == null) return;
    final regionId = _createSequenceRegionId();
    final notes = List<int?>.unmodifiable(_performance.sequenceNotes);
    final beatSeconds = 60 / _performance.tempo;
    final startSeconds =
        (_telemetry.playheadSeconds / beatSeconds).round() * beatSeconds;
    final clipId = '${track.id}-pattern-$regionId';
    try {
      await (engine as SequenceRegionEngine)
          .setSequenceRegion(regionId, startSeconds, notes);
      if (!mounted) return;
      final clip = ClipModel(
        id: clipId,
        title: 'HypnoSynth pattern',
        start: 0,
        width: 0,
        color: AetherColors.magenta,
        isDemo: false,
        isSequenceRegion: true,
        sequenceNotes: notes,
        durationSeconds: 8 * beatSeconds,
        startSeconds: startSeconds,
      );
      setState(() {
        _nativeSequenceRegionIds[clipId] = regionId;
        _confirmedClipStarts[clipId] = startSeconds;
        track!.clips.add(clip);
        _selectedTrackId = track.id;
        _selectedClipId = clip.id;
        _showMixer = true;
        _markSessionChanged();
        _pushHistory(_SequenceRegionEdit(
          trackId: track.id,
          clip: clip,
          regionId: regionId,
          presentAfterEdit: true,
        ));
      });
    } catch (error) {
      if (mounted) _reportMixerFailure('Insert HypnoSynth pattern', error);
    }
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
      final nativeId = clip == null ? null : _nativeIdForClip(clip);
      final engine = _engine;
      final sequenceRegionId =
          clip == null ? null : _nativeSequenceRegionIds[clip.id];
      if (clip?.isSequenceRegion == true &&
          track != null &&
          sequenceRegionId != null &&
          engine is SequenceRegionEngine) {
        _queueMixerAction(_commitSequenceRegionPosition(
            engine as SequenceRegionEngine,
            clip!,
            sequenceRegionId,
            clip.startSeconds));
      } else if (clip != null &&
          track != null &&
          nativeId != null &&
          engine != null) {
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
          'Saved ${document.tracks.length + document.instrumentTracks.length} tracks '
          '(${document.tracks.length} audio, ${document.instrumentTracks.length} instrument). '
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
    required Map<String, int> preparedRegionIds,
    Map<String, int> preparedSequenceRegionIds = const <String, int>{},
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
      _tracks.removeWhere((track) =>
          _nativeTrackIds.containsKey(track.id) || track.kind == 'INSTRUMENT');
      _tracks.addAll(preparedTracks);
      _showMixer = preparedTracks.isNotEmpty;
      _nativeTrackIds
        ..clear()
        ..addAll(preparedIds);
      _nativeRegionIds
        ..clear()
        ..addAll(preparedRegionIds);
      _nativeSequenceRegionIds
        ..clear()
        ..addAll(preparedSequenceRegionIds);
      _nativeTrackSources
        ..clear()
        ..addAll(preparedSources);
      for (final timer in _clipPositionTimers.values) {
        timer.cancel();
      }
      _clipPositionTimers.clear();
      _clipMoveStarts.clear();
      _undoHistory.clear();
      _redoHistory.clear();
      _confirmedClipStarts
        ..clear()
        ..addEntries(preparedTracks.expand((track) => track.clips.map(
              (clip) => MapEntry(clip.id, clip.startSeconds),
            )));
      _selectedTrackId = preparedTracks.isEmpty ? '' : preparedTracks.first.id;
      _selectedClipId =
          preparedTracks.isEmpty || preparedTracks.first.clips.isEmpty
              ? null
              : preparedTracks.first.clips.first.id;
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
      final performanceEngine = staged as PerformanceEngine;
      await _applyPerformance(performanceEngine, document.performance);
      final tracks = <TrackModel>[];
      final ids = <String, int>{};
      final regionIds = <String, int>{};
      final sequenceRegionIds = <String, int>{};
      final sources = <String, String>{};
      for (final saved in document.tracks) {
        final source = saved.sourcePath;
        final clips = <ClipModel>[];
        for (final region in saved.effectiveRegions) {
          final loaded = await staged.loadTrack(source);
          await staged.setTrackVolume(loaded.id, saved.gain);
          await staged.setTrackPan(loaded.id, saved.pan);
          await staged.muteTrack(loaded.id, saved.muted);
          await staged.soloTrack(loaded.id, saved.solo);
          await staged.setTrackStartSeconds(loaded.id, region.startSeconds);
          if (region.sourceStartSeconds > 0 || region.durationSeconds != null) {
            final regionEngine = staged;
            if (regionEngine is! AudioRegionEngine) {
              throw StateError(
                  'This engine cannot restore split audio regions.');
            }
            await (regionEngine as AudioRegionEngine).setTrackRegionSeconds(
              loaded.id,
              region.sourceStartSeconds,
              region.durationSeconds ?? loaded.durationSeconds ?? 0,
            );
          }
          ids.putIfAbsent(saved.id, () => loaded.id);
          regionIds[region.id] = loaded.id;
          clips.add(ClipModel(
            id: region.id,
            title: saved.name,
            start: 0,
            width: 0,
            color: AetherColors.sage,
            isDemo: false,
            durationSeconds: region.durationSeconds ?? loaded.durationSeconds,
            sourceDurationSeconds: loaded.durationSeconds,
            sourceStartSeconds: region.sourceStartSeconds,
            startSeconds: region.startSeconds,
          ));
        }
        sources[saved.id] = source;
        tracks.add(TrackModel(
          id: saved.id,
          name: saved.name,
          kind: 'AUDIO',
          color: AetherColors.sage,
          volume: saved.gain,
          pan: saved.pan,
          muted: saved.muted,
          solo: saved.solo,
          clips: clips,
        ));
      }
      for (final saved in document.instrumentTracks) {
        await performanceEngine.synthEvent(6, 0, saved.gain);
        await performanceEngine.synthEvent(7, 0, saved.pan);
        await performanceEngine.synthEvent(8, 0, saved.muted ? 1 : 0);
        await performanceEngine.synthEvent(9, 0, saved.solo ? 1 : 0);
        final sequenceClips = <ClipModel>[];
        if (saved.regions.isNotEmpty) {
          final sequenceEngine = staged;
          if (sequenceEngine is! SequenceRegionEngine) {
            throw StateError('This engine cannot restore HypnoSynth patterns.');
          }
          for (final region in saved.regions) {
            await (sequenceEngine as SequenceRegionEngine).setSequenceRegion(
                region.id, region.startSeconds, region.notes);
            final clipId = '${saved.id}-pattern-${region.id}';
            sequenceRegionIds[clipId] = region.id;
            sequenceClips.add(ClipModel(
              id: clipId,
              title: 'HypnoSynth pattern',
              start: 0,
              width: 0,
              color: AetherColors.magenta,
              isDemo: false,
              isSequenceRegion: true,
              sequenceNotes: List<int?>.unmodifiable(region.notes),
              durationSeconds: 8 * 60 / document.performance.tempo,
              startSeconds: region.startSeconds,
            ));
            if (region.id >= _nextSequenceRegionId) {
              _nextSequenceRegionId =
                  region.id == 0xffffffff ? 1 : region.id + 1;
            }
          }
        }
        tracks.add(TrackModel(
          id: saved.id,
          name: saved.name,
          kind: 'INSTRUMENT',
          color: AetherColors.magenta,
          clips: sequenceClips,
          volume: saved.gain,
          pan: saved.pan,
          muted: saved.muted,
          solo: saved.solo,
        ));
      }
      if (!mounted) return;
      await _adoptPreparedSession(
        preparedEngine: staged,
        preparedTracks: tracks,
        preparedIds: ids,
        preparedRegionIds: regionIds,
        preparedSequenceRegionIds: sequenceRegionIds,
        preparedSources: sources,
        title: document.title,
        path: file.path,
        performance: document.performance,
      );
      staged = null; // Ownership now belongs to the workspace.
      for (final track in tracks) {
        final source = sources[track.id];
        if (source != null) {
          for (final clip in track.clips) {
            unawaited(_loadClipWaveform(track, clip, source));
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opened ${tracks.length} tracks.')),
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
        preparedRegionIds: const {},
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
        _historyOperationPending ||
        _initializingEngine) {
      return;
    }
    final performance = engine as PerformanceEngine;
    final previous = _performance;
    final selectedPattern = _tracks
        .expand((track) => track.clips)
        .where((clip) => clip.id == _selectedClipId && clip.isSequenceRegion)
        .firstOrNull;
    final sequenceRegionId = selectedPattern == null
        ? null
        : _nativeSequenceRegionIds[selectedPattern.id];
    final selectedTrack = selectedPattern == null
        ? null
        : _tracks
            .where((track) => track.clips.contains(selectedPattern))
            .firstOrNull;
    final beforeNotes = selectedPattern == null
        ? null
        : List<int?>.unmodifiable(selectedPattern.sequenceNotes);
    final notesChanged = beforeNotes != null &&
        !_sameSequenceNotes(beforeNotes, settings.sequenceNotes);
    setState(() {
      _performance = settings;
      if (selectedPattern != null) {
        selectedPattern.sequenceNotes =
            List<int?>.unmodifiable(settings.sequenceNotes);
      }
      _markSessionChanged();
    });
    final action = _performanceChain
        .then((_) => _applyPerformance(
              performance,
              settings,
              previous: previous,
            ))
        .then((_) async {
      if (selectedPattern != null &&
          sequenceRegionId != null &&
          engine is SequenceRegionEngine) {
        await (engine as SequenceRegionEngine).setSequenceRegion(
            sequenceRegionId,
            selectedPattern.startSeconds,
            settings.sequenceNotes);
        if (notesChanged && selectedTrack != null) {
          _pushHistory(_SequenceNotesEdit(
            trackId: selectedTrack.id,
            clip: selectedPattern,
            regionId: sequenceRegionId,
            beforeNotes: beforeNotes,
            afterNotes: List<int?>.unmodifiable(settings.sequenceNotes),
          ));
        }
      }
    }).catchError((Object error) async {
      if (mounted && identical(_performance, settings)) {
        setState(() {
          _performance = previous;
          if (selectedPattern != null) {
            selectedPattern.sequenceNotes =
                List<int?>.unmodifiable(previous.sequenceNotes);
          }
        });
      }
      if (selectedPattern != null &&
          sequenceRegionId != null &&
          engine is SequenceRegionEngine) {
        try {
          await (engine as SequenceRegionEngine).setSequenceRegion(
              sequenceRegionId,
              selectedPattern.startSeconds,
              previous.sequenceNotes);
        } catch (_) {
          // Keep the visible rollback; the original native rejection is shown below.
        }
      }
      _reportMixerFailure('Instrument settings', error);
    });
    _performanceChain = action;
    _mixerActions.add(action);
    unawaited(action.whenComplete(() => _mixerActions.remove(action)));
  }

  bool _sameSequenceNotes(List<int?> left, List<int?> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
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
      case 'region.split':
        unawaited(_splitSelectedRegionAtPlayhead());
        return;
      case 'region.join':
        unawaited(_joinSelectedRegions());
        return;
      case 'region.trimStart':
        unawaited(_trimSelectedRegionAtPlayhead(trimStart: true));
        return;
      case 'region.trimEnd':
        unawaited(_trimSelectedRegionAtPlayhead(trimStart: false));
        return;
      case 'region.bounce':
        _showFeatureUnavailable('Bounce in Place');
        return;
      case 'region.deletePattern':
        unawaited(_removeSelectedPatternRegion());
        return;
      case 'edit.cut':
        if (_copySelectedItem()) {
          if (_selectedPatternRegion != null) {
            unawaited(_removeSelectedPatternRegion());
          } else {
            unawaited(_removeSelectedTrack());
          }
        }
        return;
      case 'edit.copy':
        _copySelectedItem();
        return;
      case 'edit.paste':
        unawaited(_pasteAudioTrack());
        return;
      case 'edit.duplicate':
        unawaited(_duplicateSelectedTrack());
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
        _addInstrumentTrack();
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
      case 'navigate.previous':
        unawaited(_seekPreviousBar());
        return;
      case 'navigate.next':
        unawaited(_seekNextBar());
        return;
      case 'navigate.end':
        unawaited(_seekToEnd());
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
          content: Text('Stop playback before moving a clip.'),
        ));
        Timer(
          const Duration(seconds: 2),
          () => _positionMoveDeniedShown = false,
        );
      }
      return;
    }
    final nativeId = _nativeIdForClip(clip);
    final engine = _engine;
    if (engine == null ||
        _trackOperationPending ||
        (!clip.isSequenceRegion && nativeId == null)) {
      return;
    }
    final pixelsPerSecond = timelinePixelsPerSecond(_performance.tempo);
    final beatSeconds = 60 / _performance.tempo;
    final unsnapped = clip.startSeconds + deltaPx / _zoom / pixelsPerSecond;
    final positioned = _snapToBeat
        ? (unsnapped / beatSeconds).round() * beatSeconds
        : unsnapped;
    final next = positioned.clamp(0.0, 3600.0).toDouble();
    if (clip.isSequenceRegion) {
      final regionId = _nativeSequenceRegionIds[clip.id];
      if (regionId == null || engine is! SequenceRegionEngine) return;
      final sequenceEngine = engine as SequenceRegionEngine;
      setState(() {
        clip.startSeconds = next;
        _selectedTrackId = track.id;
        _selectedClipId = clip.id;
        _markSessionChanged();
      });
      _clipPositionTimers.remove(clip.id)?.cancel();
      _clipPositionTimers[clip.id] =
          Timer(const Duration(milliseconds: 60), () {
        _clipPositionTimers.remove(clip.id);
        _queueMixerAction(_commitSequenceRegionPosition(
            sequenceEngine, clip, regionId, next));
      });
      return;
    }
    setState(() {
      clip.startSeconds = next;
      _selectedTrackId = track.id;
      _selectedClipId = clip.id;
      _markSessionChanged();
    });
    _clipPositionTimers.remove(clip.id)?.cancel();
    _clipPositionTimers[clip.id] = Timer(const Duration(milliseconds: 60), () {
      _clipPositionTimers.remove(clip.id);
      _queueMixerAction(_commitClipStart(engine, track, clip, nativeId!, next));
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
    final nativeId = _nativeIdForClip(clip);
    final engine = _engine;
    final sequenceRegionId = _nativeSequenceRegionIds[clip.id];
    if (engine == null ||
        (clip.isSequenceRegion &&
            (sequenceRegionId == null || engine is! SequenceRegionEngine)) ||
        (!clip.isSequenceRegion && nativeId == null)) {
      return;
    }
    _clipPositionTimers.remove(clip.id)?.cancel();
    final edit = _ClipMoveEdit(
      trackId: track.id,
      clipId: clip.id,
      beforeSeconds: before,
      afterSeconds: clip.startSeconds,
    );
    if (clip.isSequenceRegion) {
      _queueMixerAction(_commitSequenceRegionPosition(
          engine as SequenceRegionEngine,
          clip,
          sequenceRegionId!,
          edit.afterSeconds,
          historyEdit: edit));
    } else {
      _queueMixerAction(_commitClipStart(
          engine, track, clip, nativeId!, edit.afterSeconds,
          historyEdit: edit));
    }
  }

  Future<void> _undoClipMove() => _applyEditHistory(redo: false);

  Future<void> _redoClipMove() => _applyEditHistory(redo: true);

  void _pushHistory(Object edit) {
    _undoHistory.add(edit);
    if (_undoHistory.length > 100) _undoHistory.removeAt(0);
    _redoHistory.clear();
  }

  String _historyTrackId(Object edit) => switch (edit) {
        _ClipMoveEdit(:final trackId) => trackId,
        _RegionSplitEdit(:final trackId) => trackId,
        _RegionTrimEdit(:final trackId) => trackId,
        _SequenceRegionEdit(:final trackId) => trackId,
        _SequenceNotesEdit(:final trackId) => trackId,
        _ => '',
      };

  Future<void> _applyEditHistory({required bool redo}) async {
    if (_trackOperationPending ||
        _historyOperationPending ||
        _initializingEngine) {
      return;
    }
    await _performanceChain;
    if (!mounted) return;
    final source = redo ? _redoHistory : _undoHistory;
    if (source.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(redo
              ? 'There is no edit to redo.'
              : 'There is no edit to undo.')));
      return;
    }
    if (_telemetry.isPlaying || _isRecording) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Stop playback and recording before editing history.'),
      ));
      return;
    }
    final edit = source.last;
    _historyOperationPending = true;
    try {
      if (edit is _ClipMoveEdit) {
        await _applyClipMoveHistory(edit, redo: redo);
      } else if (edit is _RegionSplitEdit) {
        await _applyRegionSplitHistory(edit, redo: redo);
      } else if (edit is _RegionTrimEdit) {
        await _applyRegionTrimHistory(edit, redo: redo);
      } else if (edit is _SequenceRegionEdit) {
        await _applySequenceRegionHistory(edit, redo: redo);
      } else if (edit is _SequenceNotesEdit) {
        await _applySequenceNotesHistory(edit, redo: redo);
      }
    } finally {
      _historyOperationPending = false;
    }
  }

  Future<void> _applySequenceNotesHistory(
    _SequenceNotesEdit edit, {
    required bool redo,
  }) async {
    final source = redo ? _redoHistory : _undoHistory;
    final destination = redo ? _undoHistory : _redoHistory;
    final engine = _engine;
    final track = _tracks.where((item) => item.id == edit.trackId).firstOrNull;
    if (engine is! PerformanceEngine ||
        engine is! SequenceRegionEngine ||
        track == null ||
        !track.clips.contains(edit.clip)) {
      _showEngineUnavailable();
      return;
    }
    final performanceEngine = engine as PerformanceEngine;
    final sequenceEngine = engine as SequenceRegionEngine;
    final previous = List<int?>.unmodifiable(edit.clip.sequenceNotes);
    final next = redo ? edit.afterNotes : edit.beforeNotes;
    try {
      await sequenceEngine.setSequenceRegion(
          edit.regionId, edit.clip.startSeconds, next);
      for (var index = 0; index < next.length; index++) {
        if (previous[index] != next[index]) {
          await performanceEngine.synthEvent(
              5, index, next[index]?.toDouble() ?? -1);
        }
      }
      if (!mounted) return;
      setState(() {
        edit.clip.sequenceNotes = List<int?>.unmodifiable(next);
        _performance = _performance.copyWith(sequenceNotes: next);
        _markSessionChanged();
      });
      source.removeLast();
      destination.add(edit);
    } catch (error) {
      try {
        await sequenceEngine.setSequenceRegion(
            edit.regionId, edit.clip.startSeconds, previous);
        for (var index = 0; index < previous.length; index++) {
          if (previous[index] != next[index]) {
            await performanceEngine.synthEvent(
                5, index, previous[index]?.toDouble() ?? -1);
          }
        }
      } catch (_) {}
      if (mounted) _reportMixerFailure('Pattern note history', error);
    }
  }

  Future<void> _applySequenceRegionHistory(
    _SequenceRegionEdit edit, {
    required bool redo,
  }) async {
    final source = redo ? _redoHistory : _undoHistory;
    final destination = redo ? _undoHistory : _redoHistory;
    final engine = _engine;
    final track = _tracks.where((item) => item.id == edit.trackId).firstOrNull;
    if (engine is! SequenceRegionEngine || track == null) {
      _showEngineUnavailable();
      return;
    }
    final sequenceEngine = engine as SequenceRegionEngine;
    final shouldBePresent =
        redo ? edit.presentAfterEdit : !edit.presentAfterEdit;
    if (track.clips.contains(edit.clip) == shouldBePresent) {
      source.removeLast();
      destination.add(edit);
      return;
    }
    try {
      if (shouldBePresent) {
        await sequenceEngine.setSequenceRegion(
            edit.regionId, edit.clip.startSeconds, edit.clip.sequenceNotes);
        if (!mounted) {
          await sequenceEngine.removeSequenceRegion(edit.regionId);
          return;
        }
        setState(() {
          track.clips.add(edit.clip);
          _nativeSequenceRegionIds[edit.clip.id] = edit.regionId;
          _confirmedClipStarts[edit.clip.id] = edit.clip.startSeconds;
          _selectedTrackId = track.id;
          _selectedClipId = edit.clip.id;
          _markSessionChanged();
        });
      } else {
        await sequenceEngine.removeSequenceRegion(edit.regionId);
        if (!mounted) return;
        setState(() {
          track.clips.remove(edit.clip);
          _nativeSequenceRegionIds.remove(edit.clip.id);
          _confirmedClipStarts.remove(edit.clip.id);
          if (_selectedClipId == edit.clip.id) _selectedClipId = null;
          _markSessionChanged();
        });
      }
      source.removeLast();
      destination.add(edit);
    } catch (error) {
      if (mounted) _reportMixerFailure('Pattern edit history', error);
    }
  }

  Future<void> _applyClipMoveHistory(
    _ClipMoveEdit edit, {
    required bool redo,
  }) async {
    final source = redo ? _redoHistory : _undoHistory;
    final destination = redo ? _undoHistory : _redoHistory;
    final engine = _engine;
    final track = _tracks.where((item) => item.id == edit.trackId).firstOrNull;
    final clip =
        track?.clips.where((item) => item.id == edit.clipId).firstOrNull;
    final nativeId = clip == null ? null : _nativeIdForClip(clip);
    final sequenceRegionId =
        clip == null ? null : _nativeSequenceRegionIds[clip.id];
    final sequenceEngine = engine is SequenceRegionEngine;
    if (engine == null ||
        track == null ||
        clip == null ||
        (clip.isSequenceRegion &&
            (!sequenceEngine || sequenceRegionId == null)) ||
        (!clip.isSequenceRegion && nativeId == null)) {
      _showEngineUnavailable();
      return;
    }
    final previous = clip.startSeconds;
    final next = redo ? edit.afterSeconds : edit.beforeSeconds;
    _clipPositionTimers.remove(clip.id)?.cancel();
    setState(() {
      clip.startSeconds = next;
      _markSessionChanged();
    });
    try {
      if (clip.isSequenceRegion) {
        await (engine as SequenceRegionEngine)
            .setSequenceRegion(sequenceRegionId!, next, clip.sequenceNotes);
      } else {
        await engine.setTrackStartSeconds(nativeId!, next);
      }
      _confirmedClipStarts[clip.id] = next;
      source.removeLast();
      destination.add(edit);
    } catch (error) {
      final stillRegistered = clip.isSequenceRegion
          ? _nativeSequenceRegionIds[clip.id] == sequenceRegionId
          : _nativeIdForClip(clip) == nativeId;
      if (mounted && stillRegistered) {
        setState(() => clip.startSeconds = previous);
      }
      _reportMixerFailure('Clip move history', error);
    }
  }

  Future<void> _applyRegionTrimHistory(
    _RegionTrimEdit edit, {
    required bool redo,
  }) async {
    final source = redo ? _redoHistory : _undoHistory;
    final destination = redo ? _undoHistory : _redoHistory;
    final engine = _engine;
    final regionEngine = engine;
    final track = _tracks.where((item) => item.id == edit.trackId).firstOrNull;
    final nativeId = _nativeIdForClip(edit.clip);
    if (engine == null ||
        regionEngine is! AudioRegionEngine ||
        track == null ||
        nativeId == null) {
      _showEngineUnavailable();
      return;
    }
    final fromSourceStart =
        redo ? edit.beforeSourceStart : edit.afterSourceStart;
    final fromDuration = redo ? edit.beforeDuration : edit.afterDuration;
    final fromStart = redo ? edit.beforeStart : edit.afterStart;
    final toSourceStart = redo ? edit.afterSourceStart : edit.beforeSourceStart;
    final toDuration = redo ? edit.afterDuration : edit.beforeDuration;
    final toStart = redo ? edit.afterStart : edit.beforeStart;
    final toWaveform = redo ? edit.afterWaveform : edit.beforeWaveform;
    setState(() => _trackOperationPending = true);
    try {
      final audioRegionEngine = regionEngine as AudioRegionEngine;
      await audioRegionEngine.setTrackRegionSeconds(
          nativeId, toSourceStart, toDuration);
      try {
        await engine.setTrackStartSeconds(nativeId, toStart);
      } catch (_) {
        await audioRegionEngine.setTrackRegionSeconds(
            nativeId, fromSourceStart, fromDuration);
        await engine.setTrackStartSeconds(nativeId, fromStart);
        rethrow;
      }
      setState(() {
        edit.clip.sourceStartSeconds = toSourceStart;
        edit.clip.durationSeconds = toDuration;
        edit.clip.startSeconds = toStart;
        edit.clip.waveformPeaks =
            toWaveform == null ? null : List<double>.of(toWaveform);
        _confirmedClipStarts[edit.clip.id] = toStart;
        _markSessionChanged();
      });
      source.removeLast();
      destination.add(edit);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Region trim history failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _trackOperationPending = false);
    }
  }

  Future<void> _applyRegionSplitHistory(
    _RegionSplitEdit edit, {
    required bool redo,
  }) async {
    final source = redo ? _redoHistory : _undoHistory;
    final destination = redo ? _undoHistory : _redoHistory;
    final engine = _engine;
    final track = _tracks.where((item) => item.id == edit.trackId).firstOrNull;
    if (engine == null ||
        engine is! AudioRegionEngine ||
        track == null ||
        !_nativeRegionIds.containsKey(edit.originalClip.id)) {
      _showEngineUnavailable();
      return;
    }
    final regionEngine = engine as AudioRegionEngine;
    setState(() => _trackOperationPending = true);
    try {
      final doSplit = redo != edit.wasJoined;
      if (doSplit) {
        final sourcePath = _nativeTrackSources[track.id];
        if (sourcePath == null ||
            await engine.getTrackCount() >= AudioSessionDocument.maxTracks) {
          throw StateError('No audio region slot is available.');
        }
        final loaded = await engine.loadTrack(sourcePath);
        var configured = false;
        try {
          await engine.setTrackVolume(loaded.id, track.volume);
          await engine.setTrackPan(loaded.id, track.pan);
          await engine.muteTrack(loaded.id, track.muted);
          await engine.soloTrack(loaded.id, track.solo);
          await regionEngine.setTrackRegionSeconds(
            loaded.id,
            edit.rightClip.sourceStartSeconds,
            edit.rightClip.durationSeconds!,
          );
          await engine.setTrackStartSeconds(
              loaded.id, edit.rightClip.startSeconds);
          await regionEngine.setTrackRegionSeconds(
            _nativeRegionIds[edit.originalClip.id]!,
            edit.originalClip.sourceStartSeconds,
            edit.originalDuration - edit.rightClip.durationSeconds!,
          );
          configured = true;
          setState(() {
            edit.originalClip.durationSeconds =
                edit.originalDuration - edit.rightClip.durationSeconds!;
            edit.originalClip.waveformPeaks = edit.splitWaveform == null
                ? null
                : List<double>.of(edit.splitWaveform!);
            final index = track.clips.indexOf(edit.originalClip);
            track.clips.insert(index + 1, edit.rightClip);
            edit.rightNativeId = loaded.id;
            _nativeRegionIds[edit.rightClip.id] = loaded.id;
            _confirmedClipStarts[edit.rightClip.id] =
                edit.rightClip.startSeconds;
            _markSessionChanged();
          });
        } catch (_) {
          try {
            await engine.removeTrack(loaded.id);
          } catch (_) {}
          if (configured) {
            await regionEngine.setTrackRegionSeconds(
              _nativeRegionIds[edit.originalClip.id]!,
              edit.originalClip.sourceStartSeconds,
              edit.originalDuration,
            );
          }
          rethrow;
        }
      } else {
        final originalId = _nativeRegionIds[edit.originalClip.id]!;
        await regionEngine.setTrackRegionSeconds(
          originalId,
          edit.originalClip.sourceStartSeconds,
          edit.originalDuration,
        );
        try {
          await engine.removeTrack(edit.rightNativeId);
        } catch (_) {
          await regionEngine.setTrackRegionSeconds(
            originalId,
            edit.originalClip.sourceStartSeconds,
            edit.originalDuration - edit.rightClip.durationSeconds!,
          );
          rethrow;
        }
        setState(() {
          track.clips.remove(edit.rightClip);
          edit.originalClip.durationSeconds = edit.originalDuration;
          edit.originalClip.waveformPeaks = edit.originalWaveform == null
              ? null
              : List<double>.of(edit.originalWaveform!);
          _nativeRegionIds.remove(edit.rightClip.id);
          _confirmedClipStarts.remove(edit.rightClip.id);
          _selectedClipId = edit.originalClip.id;
          _markSessionChanged();
        });
      }
      source.removeLast();
      destination.add(edit);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Region edit history failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _trackOperationPending = false);
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
        _pushHistory(historyEdit);
      }
    } catch (error) {
      if (!mounted) return;
      if (_nativeIdForClip(clip) == nativeId &&
          (clip.startSeconds - seconds).abs() < 0.000001) {
        setState(() => clip.startSeconds = previous);
      }
      _reportMixerFailure('Clip position', error);
    }
  }

  Future<void> _commitSequenceRegionPosition(
      SequenceRegionEngine engine, ClipModel clip, int regionId, double seconds,
      {_ClipMoveEdit? historyEdit}) async {
    final previous = _confirmedClipStarts[clip.id] ?? 0;
    try {
      await engine.setSequenceRegion(regionId, seconds, clip.sequenceNotes);
      _confirmedClipStarts[clip.id] = seconds;
      if (historyEdit != null) _pushHistory(historyEdit);
    } catch (error) {
      if (!mounted) return;
      if (_nativeSequenceRegionIds[clip.id] == regionId &&
          (clip.startSeconds - seconds).abs() < 0.000001) {
        setState(() => clip.startSeconds = previous);
      }
      _reportMixerFailure('Pattern position', error);
    }
  }

  void _selectClip(TrackModel track, ClipModel clip) {
    setState(() {
      _selectedTrackId = track.id;
      _selectedClipId = clip.id;
      if (clip.isSequenceRegion) {
        _performance = _performance.copyWith(
            sequenceNotes: List<int?>.of(clip.sequenceNotes));
      }
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
    if (track.kind == 'INSTRUMENT') {
      _setInstrumentMixer(track, 6, value);
      return;
    }
    final ids = _nativeIdsForTrack(track);
    final engine = _engine;
    if (ids.isNotEmpty && engine == null) {
      _showEngineUnavailable();
      return;
    }
    if (_trackOperationPending) return;
    final previous = track.volume;
    setState(() {
      track.volume = value;
      if (ids.isNotEmpty) _markSessionChanged();
    });
    if (ids.isNotEmpty) {
      _queueMixerAction(_commitVolume(engine!, track, ids, value, previous));
    }
  }

  Future<void> _commitVolume(EngineController engine, TrackModel track,
      List<int> ids, double value, double previous) async {
    final applied = <int>[];
    try {
      for (final id in ids) {
        await engine.setTrackVolume(id, value);
        applied.add(id);
      }
    } catch (error) {
      if (!mounted) return;
      for (final id in applied) {
        try {
          await engine.setTrackVolume(id, previous);
        } catch (_) {}
      }
      if (track.volume == value) {
        setState(() => track.volume = previous);
      }
      _reportMixerFailure('Track volume', error);
    }
  }

  void _setTrackPan(TrackModel track, double value) {
    if (track.kind == 'INSTRUMENT') {
      _setInstrumentMixer(track, 7, value);
      return;
    }
    final ids = _nativeIdsForTrack(track);
    final engine = _engine;
    if (ids.isNotEmpty && engine == null) {
      _showEngineUnavailable();
      return;
    }
    if (_trackOperationPending) return;
    final previous = track.pan;
    setState(() {
      track.pan = value;
      if (ids.isNotEmpty) _markSessionChanged();
    });
    if (ids.isNotEmpty) {
      _queueMixerAction(_commitPan(engine!, track, ids, value, previous));
    }
  }

  Future<void> _commitPan(EngineController engine, TrackModel track,
      List<int> ids, double value, double previous) async {
    final applied = <int>[];
    try {
      for (final id in ids) {
        await engine.setTrackPan(id, value);
        applied.add(id);
      }
    } catch (error) {
      if (!mounted) return;
      for (final id in applied) {
        try {
          await engine.setTrackPan(id, previous);
        } catch (_) {}
      }
      if (track.pan == value) {
        setState(() => track.pan = previous);
      }
      _reportMixerFailure('Track pan', error);
    }
  }

  void _setTrackMute(TrackModel track, bool value) {
    if (track.kind == 'INSTRUMENT') {
      _setInstrumentMixer(track, 8, value ? 1 : 0);
      return;
    }
    final ids = _nativeIdsForTrack(track);
    final engine = _engine;
    if (ids.isNotEmpty && engine == null) {
      _showEngineUnavailable();
      return;
    }
    if (_trackOperationPending) return;
    final previous = track.muted;
    setState(() {
      track.muted = value;
      if (ids.isNotEmpty) _markSessionChanged();
    });
    if (ids.isNotEmpty) {
      _queueMixerAction(_commitMute(engine!, track, ids, value, previous));
    }
  }

  Future<void> _commitMute(EngineController engine, TrackModel track,
      List<int> ids, bool value, bool previous) async {
    final applied = <int>[];
    try {
      for (final id in ids) {
        await engine.muteTrack(id, value);
        applied.add(id);
      }
    } catch (error) {
      if (!mounted) return;
      for (final id in applied) {
        try {
          await engine.muteTrack(id, previous);
        } catch (_) {}
      }
      if (track.muted == value) {
        setState(() => track.muted = previous);
      }
      _reportMixerFailure('Track mute', error);
    }
  }

  void _setTrackSolo(TrackModel track, bool value) {
    if (track.kind == 'INSTRUMENT') {
      _setInstrumentMixer(track, 9, value ? 1 : 0);
      return;
    }
    final ids = _nativeIdsForTrack(track);
    final engine = _engine;
    if (_trackOperationPending) return;
    if (ids.isNotEmpty && engine == null) {
      _showEngineUnavailable();
      return;
    }
    final previous = track.solo;
    setState(() {
      track.solo = value;
      if (ids.isNotEmpty) _markSessionChanged();
    });
    if (ids.isNotEmpty) {
      _queueMixerAction(_commitSolo(engine!, track, ids, value, previous));
    }
  }

  Future<void> _commitSolo(EngineController engine, TrackModel track,
      List<int> ids, bool value, bool previous) async {
    final applied = <int>[];
    try {
      for (final id in ids) {
        await engine.soloTrack(id, value);
        applied.add(id);
      }
    } catch (error) {
      if (!mounted) return;
      for (final id in applied) {
        try {
          await engine.soloTrack(id, previous);
        } catch (_) {}
      }
      if (track.solo == value) {
        setState(() => track.solo = previous);
      }
      _reportMixerFailure('Track solo', error);
    }
  }

  void _setInstrumentMixer(TrackModel track, int event, double value) {
    final engine = _engine;
    if (engine == null || engine is! PerformanceEngine) {
      _showEngineUnavailable();
      return;
    }
    final performanceEngine = engine as PerformanceEngine;
    if (_trackOperationPending) return;
    final previous = switch (event) {
      6 => track.volume,
      7 => track.pan,
      8 => track.muted ? 1.0 : 0.0,
      _ => track.solo ? 1.0 : 0.0,
    };
    setState(() {
      switch (event) {
        case 6:
          track.volume = value;
        case 7:
          track.pan = value;
        case 8:
          track.muted = value >= 0.5;
        case 9:
          track.solo = value >= 0.5;
      }
      _markSessionChanged();
    });
    _queueMixerAction(() async {
      try {
        await performanceEngine.synthEvent(event, 0, value);
      } catch (error) {
        if (!mounted) return;
        setState(() {
          switch (event) {
            case 6:
              track.volume = previous;
            case 7:
              track.pan = previous;
            case 8:
              track.muted = previous >= 0.5;
            case 9:
              track.solo = previous >= 0.5;
          }
          _markSessionChanged();
        });
        _reportMixerFailure('HypnoSynth mixer', error);
      }
    }());
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
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            () => unawaited(_seekPreviousBar()),
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            () => unawaited(_seekNextBar()),
        const SingleActivator(LogicalKeyboardKey.end): () =>
            unawaited(_seekToEnd()),
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
        const SingleActivator(LogicalKeyboardKey.keyX, control: true): () {
          if (_copySelectedItem()) {
            if (_selectedPatternRegion != null) {
              unawaited(_removeSelectedPatternRegion());
            } else {
              unawaited(_removeSelectedTrack());
            }
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
            _copySelectedItem(),
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () =>
            unawaited(_pasteAudioTrack()),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): () =>
            unawaited(_duplicateSelectedTrack()),
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (_selectedClipId != null &&
              _nativeSequenceRegionIds.containsKey(_selectedClipId)) {
            unawaited(_removeSelectedPatternRegion());
          } else {
            unawaited(_removeSelectedTrack());
          }
        },
        const SingleActivator(LogicalKeyboardKey.f2): () =>
            unawaited(_renameSelectedTrack()),
        const SingleActivator(LogicalKeyboardKey.keyE,
            control: true, alt: true): () => unawaited(_exportMixdown()),
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
                                    onSeek: (seconds) =>
                                        unawaited(_seekToSeconds(seconds)),
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
                        onInsertPattern: () =>
                            unawaited(_insertSequenceRegion()),
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
                      loadedTrackCount: _nativeRegionIds.length,
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

class _SequenceRegionEdit {
  const _SequenceRegionEdit({
    required this.trackId,
    required this.clip,
    required this.regionId,
    required this.presentAfterEdit,
  });

  final String trackId;
  final ClipModel clip;
  final int regionId;
  final bool presentAfterEdit;
}

class _SequenceNotesEdit {
  const _SequenceNotesEdit({
    required this.trackId,
    required this.clip,
    required this.regionId,
    required this.beforeNotes,
    required this.afterNotes,
  });

  final String trackId;
  final ClipModel clip;
  final int regionId;
  final List<int?> beforeNotes;
  final List<int?> afterNotes;
}

class _RegionSplitEdit {
  _RegionSplitEdit({
    required this.trackId,
    required this.originalClip,
    required this.rightClip,
    required this.originalDuration,
    required this.originalWaveform,
    required this.splitWaveform,
    required this.rightNativeId,
    this.wasJoined = false,
  });

  final String trackId;
  final ClipModel originalClip;
  final ClipModel rightClip;
  final double originalDuration;
  final List<double>? originalWaveform;
  final List<double>? splitWaveform;
  int rightNativeId;
  final bool wasJoined;
}

class _RegionTrimEdit {
  const _RegionTrimEdit({
    required this.trackId,
    required this.clip,
    required this.beforeSourceStart,
    required this.beforeDuration,
    required this.beforeStart,
    required this.beforeWaveform,
    required this.afterSourceStart,
    required this.afterDuration,
    required this.afterStart,
    required this.afterWaveform,
  });

  final String trackId;
  final ClipModel clip;
  final double beforeSourceStart;
  final double beforeDuration;
  final double beforeStart;
  final List<double>? beforeWaveform;
  final double afterSourceStart;
  final double afterDuration;
  final double afterStart;
  final List<double>? afterWaveform;
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
      _MenuAction('track.rename', 'Rename Selected Track'),
      _MenuAction('track.duplicate', 'Duplicate Selected Track'),
      _MenuAction('track.delete', 'Delete Selected Track'),
    ],
    'Region': [
      _MenuAction('region.deletePattern', 'Delete HypnoSynth Pattern'),
      _MenuAction('region.split', 'Split at Playhead'),
      _MenuAction('region.join', 'Join Selected Regions'),
      _MenuAction('region.trimStart', 'Trim Start to Playhead'),
      _MenuAction('region.trimEnd', 'Trim End to Playhead'),
      _MenuAction('region.bounce', 'Bounce in Place'),
    ],
    'Navigate': [
      _MenuAction('navigate.start', 'Go to Start', 'Home'),
      _MenuAction('navigate.previous', 'Previous Bar', 'Ctrl+←'),
      _MenuAction('navigate.next', 'Next Bar', 'Ctrl+→'),
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
