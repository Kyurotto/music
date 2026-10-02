import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Silent background service that requests the device's optimal refresh rate
/// (e.g. 60Hz, 120Hz, or 144Hz depending on phone hardware and OS).
class DisplayRateService {
  DisplayRateService._();
  static final DisplayRateService instance = DisplayRateService._();

  static const MethodChannel _channel = MethodChannel('com.example.music/display_rate');

  bool _initialized = false;
  double _activeRefreshRate = 60.0;
  List<double> _supportedRates = const [60.0];

  double get activeRefreshRate => _activeRefreshRate;
  List<double> get supportedRates => _supportedRates;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // In unit/widget tests, avoid hardware platform channel lookups
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final List<dynamic>? rawRates =
            await _channel.invokeMethod<List<dynamic>>('getSupportedRefreshRates');
        if (rawRates != null && rawRates.isNotEmpty) {
          _supportedRates = rawRates.map((e) => (e as num).toDouble()).toList();
        }

        final num? activeRate = await _channel.invokeMethod<num>(
          'setRefreshRate',
          {'rate': 0}, // 0 tells the native OS to pick the optimal mode for this phone
        );

        if (activeRate != null && activeRate > 0) {
          _activeRefreshRate = activeRate.toDouble();
        }
      } catch (e) {
        debugPrint('[DisplayRateService] Note: $e');
      }
    }
  }
}
