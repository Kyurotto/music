import 'package:flutter/material.dart';

/// Represents a distinct sound equalization curve with 5 frequency bands.
class EqualizerPreset {
  final String name;
  final String description;
  final IconData icon;
  /// Band values in dB (-10.0 to +10.0) for:
  /// [0] 60 Hz (Sub-Bass)
  /// [1] 230 Hz (Bass)
  /// [2] 910 Hz (Midrange)
  /// [3] 3.6 kHz (Upper Mid / Treble)
  /// [4] 14 kHz (High Treble / Air)
  final List<double> bands;
  /// Subtle dynamic gain factor applied to overall volume/headroom.
  final double gainFactor;

  const EqualizerPreset({
    required this.name,
    required this.description,
    required this.icon,
    required this.bands,
    this.gainFactor = 1.0,
  });

  static const List<String> frequencyLabels = [
    '60 Hz',
    '230 Hz',
    '910 Hz',
    '3.6 kHz',
    '14 kHz',
  ];

  static const List<EqualizerPreset> all = [
    EqualizerPreset(
      name: 'Flat',
      description: 'Natural baseline sound with zero coloration.',
      icon: Icons.linear_scale_rounded,
      bands: [0.0, 0.0, 0.0, 0.0, 0.0],
      gainFactor: 1.0,
    ),
    EqualizerPreset(
      name: 'Hip Hop',
      description: 'Punchy 808 sub-bass, warm lows, and crisp rhythmic treble.',
      icon: Icons.speaker_group_rounded,
      bands: [6.0, 4.0, 1.0, 2.0, 4.0],
      gainFactor: 1.04,
    ),
    EqualizerPreset(
      name: 'Jazz',
      description: 'Silky smooth timbre, warm acoustic bass, and open room feel.',
      icon: Icons.music_note_rounded,
      bands: [3.5, 2.0, -1.0, 2.0, 3.5],
      gainFactor: 1.0,
    ),
    EqualizerPreset(
      name: 'Pop',
      description: 'Lush vocal forwardness, sparkling highs, and controlled lows.',
      icon: Icons.star_rounded,
      bands: [-1.0, 2.5, 4.5, 3.0, -0.5],
      gainFactor: 1.02,
    ),
    EqualizerPreset(
      name: 'Rock',
      description: 'Electric guitar crunch, driving kick drum, and aggressive presence.',
      icon: Icons.electric_bolt_rounded,
      bands: [5.5, 3.5, -1.5, 3.5, 5.0],
      gainFactor: 1.05,
    ),
    EqualizerPreset(
      name: 'FX Booster',
      description: 'Maximum dynamic spatial widening, heightened sub-bass, and brilliant FX air.',
      icon: Icons.auto_awesome_rounded,
      bands: [6.5, 4.5, 2.0, 5.5, 7.0],
      gainFactor: 1.08,
    ),
    EqualizerPreset(
      name: 'Classical',
      description: 'Orchestral dynamics, string delicacy, and full concert hall resonance.',
      icon: Icons.audiotrack_rounded,
      bands: [4.0, 3.0, 1.5, 3.0, 4.0],
      gainFactor: 1.01,
    ),
    EqualizerPreset(
      name: 'Folk',
      description: 'Intimate acoustic guitar body, raw vocals, and mellow warmth.',
      icon: Icons.eco_rounded,
      bands: [2.0, 1.5, 0.5, 2.0, 1.5],
      gainFactor: 1.0,
    ),
    EqualizerPreset(
      name: 'Heavy Metal',
      description: 'Scooped midrange, roaring power chords, and thunderous double-kick.',
      icon: Icons.surround_sound_rounded,
      bands: [7.0, 3.0, -2.5, 4.5, 6.5],
      gainFactor: 1.06,
    ),
    EqualizerPreset(
      name: 'Bass Boost',
      description: 'Deep resonant low frequencies for high-energy beats.',
      icon: Icons.graphic_eq_rounded,
      bands: [7.0, 5.0, 1.0, 0.0, 0.0],
      gainFactor: 1.05,
    ),
    EqualizerPreset(
      name: 'Acoustic',
      description: 'Clarity for unplugged wooden instruments and ambient room mics.',
      icon: Icons.nature_people_rounded,
      bands: [3.5, 2.5, 1.0, 3.0, 2.5],
      gainFactor: 1.0,
    ),
    EqualizerPreset(
      name: 'Electronic',
      description: 'Tight synthetic sub-bass and sharp synth leads.',
      icon: Icons.memory_rounded,
      bands: [5.0, 3.5, -1.0, 2.5, 4.5],
      gainFactor: 1.04,
    ),
    EqualizerPreset(
      name: 'Vocal Booster',
      description: 'Brings lead vocals directly to the front of the mix.',
      icon: Icons.mic_external_on_rounded,
      bands: [-2.0, 0.5, 5.5, 4.0, 0.5],
      gainFactor: 1.02,
    ),
  ];

  static List<String> get presetNames => all.map((e) => e.name).toList();

  /// Resolves any preset name, tolerating variations and typos like 'heave metal' or 'hip-hop'.
  static EqualizerPreset getByName(String? name) {
    if (name == null || name.trim().isEmpty) return all.first;
    final clean = name.trim().toLowerCase().replaceAll('-', ' ');
    if (clean.contains('heave') || clean.contains('metal')) {
      return all.firstWhere((p) => p.name == 'Heavy Metal');
    }
    if (clean.contains('fx') || clean.contains('booster') && clean.contains('fx')) {
      return all.firstWhere((p) => p.name == 'FX Booster');
    }
    for (final preset in all) {
      final pClean = preset.name.toLowerCase().replaceAll('-', ' ');
      if (pClean == clean) return preset;
    }
    for (final preset in all) {
      final pClean = preset.name.toLowerCase().replaceAll('-', ' ');
      if (pClean.contains(clean) || clean.contains(pClean)) return preset;
    }
    return all.first;
  }
}
