import 'package:flutter_test/flutter_test.dart';
import 'package:music/models/equalizer_preset.dart';
import 'package:music/services/audio_equalizer_service.dart';

void main() {
  group('EqualizerPreset', () {
    test('every preset exposes a five-band curve', () {
      for (final preset in EqualizerPreset.all) {
        expect(preset.bands.length, EqualizerPreset.frequencyLabels.length);
      }
    });

    test('custom preset resolves by name', () {
      expect(EqualizerPreset.getByName('Custom').name, 'Custom');
      expect(EqualizerPreset.getByName('custom').name, 'Custom');
    });

    test('customWithBands keeps the edited curve', () {
      final preset = EqualizerPreset.customWithBands([1, 2, 3, 4, 5]);
      expect(preset.name, EqualizerPreset.custom.name);
      expect(preset.bands, [1, 2, 3, 4, 5]);
    });
  });

  group('AudioEqualizerService.gainAtFrequency', () {
    const curve = [6.0, 4.0, 1.0, 2.0, 4.0];

    test('uses the edge bands outside the mapped range', () {
      expect(AudioEqualizerService.gainAtFrequency(20, curve), 6.0);
      expect(AudioEqualizerService.gainAtFrequency(20000, curve), 4.0);
    });

    test('returns the matching band at each anchor frequency', () {
      for (var i = 0; i < AudioEqualizerService.anchorFrequencies.length; i++) {
        expect(
          AudioEqualizerService.gainAtFrequency(
            AudioEqualizerService.anchorFrequencies[i],
            curve,
          ),
          closeTo(curve[i], 0.001),
        );
      }
    });

    test('interpolates smoothly between anchors', () {
      final midpoint = AudioEqualizerService.gainAtFrequency(117, curve);
      expect(midpoint, greaterThan(4.0));
      expect(midpoint, lessThan(6.0));
    });

    test('handles a single-band curve without dividing by zero', () {
      expect(AudioEqualizerService.gainAtFrequency(910, [3.0]), 3.0);
    });
  });

  group('AudioEqualizerService.scaleBandsToRange', () {
    test('scales the whole curve into a narrow hardware range', () {
      final scaled = AudioEqualizerService.scaleBandsToRange(
        [6.0, 4.0, 1.0, 2.0, 4.0],
        -1.5,
        1.5,
      );
      expect(scaled, [1.5, 1.0, 0.25, 0.5, 1.0]);
    });

    test('keeps a curve that already fits the hardware range', () {
      expect(
        AudioEqualizerService.scaleBandsToRange(
          [1.0, -0.5, 0.0, 0.5, 1.5],
          -1.5,
          1.5,
        ),
        [1.0, -0.5, 0.0, 0.5, 1.5],
      );
    });

    test('scales down a deep cut as well as a boost', () {
      final scaled = AudioEqualizerService.scaleBandsToRange(
        [-8.0, 0.0, 4.0, 0.0, 0.0],
        -2.0,
        2.0,
      );
      expect(scaled.first, -2.0);
      expect(scaled[2], 1.0);
    });

    test('handles an empty curve', () {
      expect(AudioEqualizerService.scaleBandsToRange([], -1.5, 1.5), isEmpty);
    });
  });
}
