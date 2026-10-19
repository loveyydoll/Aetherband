class PerformanceSettings {
  const PerformanceSettings(
      {this.preset = 0,
      this.macros = const [0.42, 0.38, 0.55, 0.36, 0.7],
      this.tempo = 92,
      this.metronome = false,
      this.sequence = false,
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
  final bool metronome;
  final bool sequence;
  final double master;

  PerformanceSettings copyWith(
          {int? preset,
          List<double>? macros,
          double? tempo,
          bool? metronome,
          bool? sequence,
          double? master}) =>
      PerformanceSettings(
          preset: preset ?? this.preset,
          macros: macros ?? this.macros,
          tempo: tempo ?? this.tempo,
          metronome: metronome ?? this.metronome,
          sequence: sequence ?? this.sequence,
          master: master ?? this.master);

  Map<String, Object> toJson() => {
        'preset': preset,
        'macros': macros,
        'tempo': tempo,
        'metronome': metronome,
        'sequence': sequence,
        'master': master
      };

  factory PerformanceSettings.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid instrument settings.');
    }
    final preset = value['preset'];
    final macros = value['macros'];
    final tempo = value['tempo'];
    final master = value['master'];
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
        master is! num ||
        !master.isFinite ||
        master < 0 ||
        master > 1 ||
        value['metronome'] is! bool ||
        value['sequence'] is! bool) {
      throw const FormatException(
          'Invalid instrument or transport parameters.');
    }
    return PerformanceSettings(
        preset: preset,
        macros:
            List<double>.unmodifiable(macros.map((v) => (v as num).toDouble())),
        tempo: tempo.toDouble(),
        master: master.toDouble(),
        metronome: value['metronome'] as bool,
        sequence: value['sequence'] as bool);
  }
}
