const defaultHypnoSequence = <int?>[
  50,
  57,
  60,
  57,
  53,
  60,
  65,
  60,
  48,
  55,
  60,
  62,
  45,
  52,
  57,
  64,
];

class PerformanceSettings {
  const PerformanceSettings(
      {this.preset = 0,
      this.macros = const [0.42, 0.38, 0.55, 0.36, 0.7],
      this.tempo = 92,
      this.beatsPerBar = 4,
      this.metronome = false,
      this.sequence = false,
      this.sequenceNotes = defaultHypnoSequence,
      this.master = 0.8});

  static const presets = ['Morning Haze', 'Nervous Current', 'Submerged'];
  static const names = ['Tone', 'Motion', 'Space', 'Drift', 'Level'];
  static const presetMacros = [
    [0.42, 0.38, 0.55, 0.36, 0.7],
    [0.68, 0.65, 0.28, 0.22, 0.7],
    [0.18, 0.18, 0.18, 0.12, 0.7],
  ];
  final int preset;
  final List<double> macros;
  final double tempo;
  final int beatsPerBar;
  final bool metronome;
  final bool sequence;
  final List<int?> sequenceNotes;
  final double master;

  PerformanceSettings copyWith(
          {int? preset,
          List<double>? macros,
          double? tempo,
          int? beatsPerBar,
          bool? metronome,
          bool? sequence,
          List<int?>? sequenceNotes,
          double? master}) =>
      PerformanceSettings(
          preset: preset ?? this.preset,
          macros: macros ?? this.macros,
          tempo: tempo ?? this.tempo,
          beatsPerBar: beatsPerBar ?? this.beatsPerBar,
          metronome: metronome ?? this.metronome,
          sequence: sequence ?? this.sequence,
          sequenceNotes: sequenceNotes ?? this.sequenceNotes,
          master: master ?? this.master);

  Map<String, Object> toJson() => {
        'preset': preset,
        'macros': macros,
        'tempo': tempo,
        'beatsPerBar': beatsPerBar,
        'metronome': metronome,
        'sequence': sequence,
        'sequenceNotes': sequenceNotes,
        'master': master
      };

  factory PerformanceSettings.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid instrument settings.');
    }
    final preset = value['preset'];
    final macros = value['macros'];
    final tempo = value['tempo'];
    final beatsPerBar = value['beatsPerBar'] ?? 4;
    final master = value['master'];
    final sequenceNotes = value['sequenceNotes'] ?? defaultHypnoSequence;
    if (preset is! int ||
        preset < 0 ||
        preset >= presets.length ||
        macros is! List ||
        macros.length != 5 ||
        macros.any((v) => v is! num || !v.isFinite || v < 0 || v > 1) ||
        tempo is! num ||
        !tempo.isFinite ||
        tempo < 30 ||
        tempo > 300 ||
        beatsPerBar is! int ||
        beatsPerBar < 2 ||
        beatsPerBar > 7 ||
        master is! num ||
        !master.isFinite ||
        master < 0 ||
        master > 1 ||
        value['metronome'] is! bool ||
        value['sequence'] is! bool ||
        sequenceNotes is! List ||
        sequenceNotes.length != 16 ||
        sequenceNotes.any((note) =>
            note != null && (note is! int || note < 0 || note > 127))) {
      throw const FormatException(
          'Invalid instrument or transport parameters.');
    }
    return PerformanceSettings(
        preset: preset,
        macros:
            List<double>.unmodifiable(macros.map((v) => (v as num).toDouble())),
        tempo: tempo.toDouble(),
        beatsPerBar: beatsPerBar,
        master: master.toDouble(),
        metronome: value['metronome'] as bool,
        sequence: value['sequence'] as bool,
        sequenceNotes:
            List<int?>.unmodifiable(sequenceNotes.map((note) => note as int?)));
  }
}
