import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../performance_settings.dart';
import '../theme.dart';

class HypnoSynthPanel extends StatefulWidget {
  const HypnoSynthPanel(
      {required this.settings,
      required this.enabled,
      required this.onSettings,
      required this.onNote,
      required this.onPanic,
      required this.onAudition,
      required this.onMixer,
      required this.onInsertPattern,
      super.key});
  final PerformanceSettings settings;
  final bool enabled;
  final ValueChanged<PerformanceSettings> onSettings;
  final void Function(int, bool) onNote;
  final VoidCallback onPanic;
  final VoidCallback onAudition;
  final VoidCallback onMixer;
  final VoidCallback onInsertPattern;
  @override
  State<HypnoSynthPanel> createState() => _HypnoSynthPanelState();
}

class _HypnoSynthPanelState extends State<HypnoSynthPanel> {
  final FocusNode _keyboard = FocusNode(debugLabel: 'HypnoSynth keyboard');
  final Set<int> _held = {};
  static const _keys = [
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyE,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.keyF,
    LogicalKeyboardKey.keyT,
    LogicalKeyboardKey.keyG,
    LogicalKeyboardKey.keyY,
    LogicalKeyboardKey.keyH,
    LogicalKeyboardKey.keyU,
    LogicalKeyboardKey.keyJ,
    LogicalKeyboardKey.keyK
  ];
  static const _labels = [
    'C',
    'C♯',
    'D',
    'D♯',
    'E',
    'F',
    'F♯',
    'G',
    'G♯',
    'A',
    'A♯',
    'B',
    'C'
  ];
  static const _pitchLabels = [
    'C',
    'C♯',
    'D',
    'D♯',
    'E',
    'F',
    'F♯',
    'G',
    'G♯',
    'A',
    'A♯',
    'B',
  ];

  String _noteName(int? note) =>
      note == null ? 'Rest' : '${_pitchLabels[note % 12]}${note ~/ 12 - 1}';

  void _setStep(int index, int? note) {
    if (!widget.enabled) return;
    final notes = [...widget.settings.sequenceNotes];
    notes[index] = note;
    widget.onSettings(widget.settings.copyWith(sequenceNotes: notes));
  }

  void _toggleStep(int index) {
    final current = widget.settings.sequenceNotes[index];
    _setStep(index, current == null ? defaultHypnoSequence[index] : null);
  }

  void _note(int note, bool down) {
    if (!widget.enabled) return;
    if (down ? _held.add(note) : _held.remove(note)) {
      widget.onNote(note, down);
      setState(() {});
    }
  }

  void _release() {
    for (final note in _held.toList()) {
      widget.onNote(note, false);
    }
    if (_held.isNotEmpty) setState(_held.clear);
  }

  @override
  void dispose() {
    _keyboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Container(
      height: 292,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
          color: AetherColors.panel,
          border: Border(top: BorderSide(color: AetherColors.raised))),
      child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
              width: 1000,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.graphic_eq,
                          color: AetherColors.magenta, size: 20),
                      const SizedBox(width: 8),
                      const Text('HYPNOSYNTH',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, letterSpacing: 2)),
                      const SizedBox(width: 18),
                      DropdownButton<int>(
                          value: s.preset,
                          items: [
                            for (var i = 0; i < 3; i++)
                              DropdownMenuItem(
                                  value: i,
                                  child: Text(PerformanceSettings.presets[i]))
                          ],
                          onChanged: !widget.enabled
                              ? null
                              : (value) {
                                  if (value != null) {
                                    widget.onSettings(s.copyWith(
                                        preset: value,
                                        macros: PerformanceSettings
                                            .presetMacros[value]));
                                  }
                                }),
                      const SizedBox(width: 16),
                      TextButton.icon(
                          onPressed: widget.enabled ? widget.onAudition : null,
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('Play original phrase')),
                      TextButton.icon(
                        onPressed:
                            widget.enabled ? widget.onInsertPattern : null,
                        icon: const Icon(Icons.add_box_outlined, size: 18),
                        label: const Text('Add pattern to arrangement'),
                      ),
                      TextButton(
                          onPressed: widget.enabled
                              ? () {
                                  _release();
                                  widget.onPanic();
                                }
                              : null,
                          child: const Text('Panic')),
                      const Spacer(),
                      TextButton(
                          onPressed: () {
                            _release();
                            widget.onMixer();
                          },
                          child: const Text('Mixer')),
                    ]),
                    Row(children: [
                      for (var i = 0; i < 5; i++)
                        SizedBox(
                            width: 150,
                            child: Column(children: [
                              Text(PerformanceSettings.names[i],
                                  style: const TextStyle(fontSize: 11)),
                              Slider(
                                  value: s.macros[i],
                                  semanticFormatterCallback: (v) =>
                                      '${(v * 100).round()} percent',
                                  onChanged: !widget.enabled
                                      ? null
                                      : (value) {
                                          final macros = [...s.macros];
                                          macros[i] = value;
                                          widget.onSettings(
                                              s.copyWith(macros: macros));
                                        }),
                            ])),
                      SizedBox(
                          width: 200,
                          child: Column(children: [
                            const Text('Master',
                                style: TextStyle(fontSize: 11)),
                            Slider(
                                value: s.master,
                                onChanged: !widget.enabled
                                    ? null
                                    : (v) => widget
                                        .onSettings(s.copyWith(master: v))),
                          ]))
                    ]),
                    Row(children: [
                      Focus(
                          focusNode: _keyboard,
                          onFocusChange: (focused) {
                            if (!focused) _release();
                          },
                          onKeyEvent: (_, event) {
                            if (HardwareKeyboard.instance.isControlPressed ||
                                HardwareKeyboard.instance.isAltPressed) {
                              return KeyEventResult.ignored;
                            }
                            final key = _keys.indexOf(event.logicalKey);
                            if (key < 0 || !widget.enabled) {
                              return KeyEventResult.ignored;
                            }
                            if (event is KeyDownEvent) _note(60 + key, true);
                            if (event is KeyUpEvent) _note(60 + key, false);
                            return KeyEventResult.handled;
                          },
                          child: Row(children: [
                            for (var i = 0; i < 13; i++)
                              Semantics(
                                  label: 'Play ${_labels[i]}${i == 12 ? 5 : 4}',
                                  button: true,
                                  child: Listener(
                                      onPointerDown: (_) {
                                        _keyboard.requestFocus();
                                        _note(60 + i, true);
                                      },
                                      onPointerUp: (_) => _note(60 + i, false),
                                      onPointerCancel: (_) =>
                                          _note(60 + i, false),
                                      child: Container(
                                          width: 35,
                                          height: 52,
                                          margin:
                                              const EdgeInsets.only(right: 2),
                                          alignment: Alignment.bottomCenter,
                                          padding:
                                              const EdgeInsets.only(bottom: 6),
                                          color: _held.contains(60 + i)
                                              ? AetherColors.sage
                                              : _labels[i].contains('♯')
                                                  ? AetherColors.background
                                                  : AetherColors.paper,
                                          child: Text(_labels[i],
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: _labels[i]
                                                              .contains('♯') &&
                                                          !_held
                                                              .contains(60 + i)
                                                      ? AetherColors.paper
                                                      : AetherColors
                                                          .background))))),
                          ])),
                      const SizedBox(width: 16),
                      const Text('BPM'),
                      IconButton(
                          tooltip: 'Decrease tempo',
                          onPressed: !widget.enabled
                              ? null
                              : () => widget.onSettings(s.copyWith(
                                  tempo: (s.tempo - 1).clamp(30, 300))),
                          icon: const Icon(Icons.remove, size: 16)),
                      Text(s.tempo.toStringAsFixed(0)),
                      IconButton(
                          tooltip: 'Increase tempo',
                          onPressed: !widget.enabled
                              ? null
                              : () => widget.onSettings(s.copyWith(
                                  tempo: (s.tempo + 1).clamp(30, 300))),
                          icon: const Icon(Icons.add, size: 16)),
                      Checkbox(
                          value: s.metronome,
                          onChanged: !widget.enabled
                              ? null
                              : (v) =>
                                  widget.onSettings(s.copyWith(metronome: v))),
                      const Text('Click'),
                      Checkbox(
                          value: s.sequence,
                          onChanged: !widget.enabled
                              ? null
                              : (v) =>
                                  widget.onSettings(s.copyWith(sequence: v))),
                      const Text('Sequence'),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      const SizedBox(
                        width: 92,
                        child: Text('16 STEPS',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1)),
                      ),
                      for (var i = 0; i < s.sequenceNotes.length; i++)
                        SizedBox(
                          width: 54,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${i + 1}'.padLeft(2, '0'),
                                  style: const TextStyle(
                                      fontSize: 9,
                                      color: AetherColors.secondaryText)),
                              IconButton(
                                tooltip: s.sequenceNotes[i] == null
                                    ? 'Enable step ${i + 1}'
                                    : 'Rest on step ${i + 1}',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                    width: 24, height: 24),
                                iconSize: 16,
                                onPressed: widget.enabled
                                    ? () => _toggleStep(i)
                                    : null,
                                icon: Icon(
                                  s.sequenceNotes[i] == null
                                      ? Icons.add_circle_outline
                                      : Icons.remove_circle,
                                  color: s.sequenceNotes[i] == null
                                      ? AetherColors.secondaryText
                                      : AetherColors.magenta,
                                ),
                              ),
                              PopupMenuButton<int>(
                                tooltip: 'Set step ${i + 1} note',
                                padding: EdgeInsets.zero,
                                enabled: widget.enabled,
                                onSelected: (note) => _setStep(i, note),
                                itemBuilder: (_) => [
                                  for (var note = 36; note <= 84; note++)
                                    PopupMenuItem(
                                        value: note,
                                        child: Text(_noteName(note))),
                                ],
                                child: Text(
                                  s.sequenceNotes[i] == null
                                      ? '—'
                                      : _noteName(s.sequenceNotes[i]),
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: s.sequenceNotes[i] == null
                                        ? AetherColors.secondaryText
                                        : AetherColors.paper,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ]),
                    const SizedBox(height: 3),
                    Text(
                        widget.enabled
                            ? 'Edit the 16-step synth sequence · Tap +/− to add rests · Choose a note · Keys A W S E D F T G Y H U J K'
                            : 'Connect the native audio engine to play HypnoSynth',
                        style: const TextStyle(
                            fontSize: 10, color: AetherColors.secondaryText)),
                  ]))),
    );
  }
}
