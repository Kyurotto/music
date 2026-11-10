import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// Applies the 5-band preset curve to the native audio pipeline.
///
/// Two Android backends are used:
///
/// 1. `DynamicsProcessing` (API 28+), exposed through a small MethodChannel.
///    Its pre-EQ stage has a +/-12 dB range, so presets keep their intended
///    shape instead of being flattened by a narrow hardware equalizer.
/// 2. `just_audio`'s [AndroidEqualizer] as a fallback. Some devices only
///    expose a +/-1.5 dB range here; the curve is scaled down proportionally
///    so it still keeps its shape.
///
/// Other platforms (iOS, Windows, web) have no equivalent effect in
/// `just_audio`, so [applyBands] becomes a safe no-op there.
class AudioEqualizerService {
  AudioEqualizerService();

  static const MethodChannel _nativeChannel = MethodChannel(
    'com.example.music/equalizer',
  );

  final AndroidEqualizer _effect = AndroidEqualizer();

  /// Effect instance that must be passed to [AudioPipeline] on Android.
  AndroidEqualizer get effect => _effect;

  /// Whether a real equalizer can be applied on the current platform.
  static bool get isPlatformSupported => !kIsWeb && Platform.isAndroid;

  /// Frequencies represented by [EqualizerPreset.bands], lowest first.
  static const List<double> anchorFrequencies = <double>[
    60,
    230,
    910,
    3600,
    14000,
  ];

  AndroidEqualizerParameters? _parameters;
  Future<void>? _ready;
  List<double> _targetBands = const <double>[0, 0, 0, 0, 0];
  bool _disposed = false;

  /// Whether the native `DynamicsProcessing` backend is available.
  bool? _nativeSupported;
  bool _nativeActive = false;
  bool _androidInitialized = false;
  int? _sessionId;

  /// Enables the effect and waits for the platform to publish its band layout.
  ///
  /// The parameters only become available once the player's platform is
  /// active (first audio source load), so this future can stay pending until
  /// then. Repeated calls share the same future.
  Future<void> initialize() {
    if (!isPlatformSupported) return Future<void>.value();
    return _ready ??= _initialize();
  }

  Future<void> _initialize() async {
    _nativeSupported = await _isNativeSupported();
    if (_disposed) return;

    if (_nativeSupported == true) {
      debugPrint(
        '[AudioEqualizer] DynamicsProcessing available; '
        'waiting for the player audio session',
      );
      final sessionId = _sessionId;
      if (sessionId != null) {
        await _attachNative(sessionId, _targetBands);
      }
      return;
    }

    await _initializeAndroidEqualizer();
  }

  Future<bool> _isNativeSupported() async {
    try {
      final supported = await _nativeChannel.invokeMethod<bool>('isSupported');
      return supported ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('[AudioEqualizer] Native support check failed: $e');
      return false;
    }
  }

  Future<void> _initializeAndroidEqualizer() async {
    if (_androidInitialized) {
      if (_parameters != null) await _applyAndroidBands(_targetBands);
      return;
    }
    _androidInitialized = true;
    try {
      await _effect.setEnabled(true);
      final parameters = await _effect.parameters;
      if (_disposed) return;
      _parameters = parameters;
      await _applyAndroidBands(_targetBands);
    } catch (e) {
      debugPrint('[AudioEqualizer] AndroidEqualizer initialization failed: $e');
    }
  }

  /// Called whenever `just_audio` publishes a new native audio session id.
  ///
  /// The session can change when the platform recreates its audio track, so
  /// the native effect is re-attached to keep the preset active.
  Future<void> setAudioSessionId(int? sessionId) async {
    if (!isPlatformSupported || _disposed) return;
    if (_sessionId == sessionId) return;
    _sessionId = sessionId;

    await initialize();
    if (_disposed) return;

    if (_nativeSupported != true) return;

    if (sessionId == null) {
      _nativeActive = false;
      await _releaseNative();
      return;
    }
    await _attachNative(sessionId, _targetBands);
  }

  /// Applies [bands] (dB, -10..+10, low to high) to the native equalizer.
  ///
  /// The call is safe before the first track is loaded: the latest curve is
  /// stored and pushed as soon as the platform parameters are available.
  Future<void> applyBands(List<double> bands) async {
    _targetBands = List<double>.from(bands);
    if (!isPlatformSupported) return;
    try {
      await initialize();
      if (_disposed) return;

      if (_nativeSupported == true) {
        // The session is not ready yet; setAudioSessionId() will attach with
        // the latest target curve.
        if (!_nativeActive) return;
        final applied = await _applyNativeBands(_targetBands);
        if (!applied) await _useAndroidFallback();
        return;
      }

      if (_parameters == null) return;
      await _applyAndroidBands(_targetBands);
    } catch (e) {
      debugPrint('[AudioEqualizer] Failed to apply bands: $e');
    }
  }

  Future<void> _attachNative(int sessionId, List<double> bands) async {
    try {
      final attached = await _nativeChannel.invokeMethod<bool>('attach', {
        'sessionId': sessionId,
        'bands': bands,
      });
      if (_disposed) return;

      if (attached == true) {
        _nativeActive = true;
        // Defensive: never stack the platform equalizer on top of the
        // native one. just_audio keeps the effect attached but bypassed.
        if (_effect.enabled) {
          await _effect.setEnabled(false);
        }
        return;
      }

      debugPrint(
        '[AudioEqualizer] DynamicsProcessing attach refused; '
        'falling back to AndroidEqualizer',
      );
      await _useAndroidFallback();
    } on MissingPluginException {
      await _useAndroidFallback();
    } catch (e) {
      debugPrint('[AudioEqualizer] Native attach failed: $e');
      await _useAndroidFallback();
    }
  }

  Future<bool> _applyNativeBands(List<double> bands) async {
    try {
      final applied = await _nativeChannel.invokeMethod<bool>('applyBands', {
        'bands': bands,
      });
      return applied ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('[AudioEqualizer] Native band update failed: $e');
      return false;
    }
  }

  Future<void> _releaseNative() async {
    try {
      await _nativeChannel.invokeMethod<void>('release');
    } catch (_) {}
  }

  Future<void> _useAndroidFallback() async {
    _nativeSupported = false;
    _nativeActive = false;
    await _releaseNative();
    await _initializeAndroidEqualizer();
  }

  Future<void> _applyAndroidBands(List<double> bands) async {
    final parameters = _parameters;
    if (parameters == null || parameters.bands.isEmpty) return;

    final scaled = scaleBandsToRange(
      bands,
      parameters.minDecibels,
      parameters.maxDecibels,
    );
    debugPrint(
      '[AudioEqualizer] Applying ${scaled.map((b) => b.toStringAsFixed(1)).join("/")} '
      'dB to ${parameters.bands.length} hardware bands '
      '(${parameters.minDecibels.toStringAsFixed(1)}..'
      '${parameters.maxDecibels.toStringAsFixed(1)} dB)',
    );

    for (final band in parameters.bands) {
      final target = gainAtFrequency(
        band.centerFrequency,
        scaled,
      ).clamp(parameters.minDecibels, parameters.maxDecibels).toDouble();
      // Avoid a platform round-trip when the value did not really change.
      if ((band.gain - target).abs() < 0.05) continue;
      try {
        await band.setGain(target);
      } catch (e) {
        debugPrint(
          '[AudioEqualizer] Band ${band.index} (${band.centerFrequency} Hz) '
          'failed: $e',
        );
      }
    }
  }

  /// Scales an arbitrary curve down so it fits inside a hardware gain range.
  ///
  /// Scaling the whole curve (instead of clamping each band) preserves the
  /// relative shape of the preset, which matters on devices whose equalizer
  /// only exposes a very narrow range (e.g. +/-1.5 dB).
  @visibleForTesting
  static List<double> scaleBandsToRange(
    List<double> bands,
    double minDecibels,
    double maxDecibels,
  ) {
    if (bands.isEmpty) return const <double>[];

    final maxBoost = bands.reduce(math.max);
    final maxCut = -bands.reduce(math.min);

    final boostScale = maxBoost > maxDecibels && maxBoost > 0
        ? maxDecibels / maxBoost
        : 1.0;
    final cutScale = maxCut > -minDecibels && maxCut > 0
        ? -minDecibels / maxCut
        : 1.0;
    final scale = math.min(boostScale, cutScale).clamp(0.0, 1.0).toDouble();

    return bands.map((band) => band * scale).toList(growable: false);
  }

  /// Interpolates the preset curve at [frequency].
  ///
  /// Interpolation is logarithmic so a device with more (or fewer) hardware
  /// bands than the five preset anchors still receives a smooth curve.
  @visibleForTesting
  static double gainAtFrequency(double frequency, List<double> bands) {
    if (bands.isEmpty) return 0;
    if (bands.length == 1) return bands.first;

    double valueAtAnchor(int anchorIndex) {
      final position =
          anchorIndex * (bands.length - 1) / (anchorFrequencies.length - 1);
      final lower = position.floor();
      final upper = position.ceil();
      if (lower == upper) return bands[lower];
      final t = position - lower;
      return bands[lower] + (bands[upper] - bands[lower]) * t;
    }

    if (frequency <= anchorFrequencies.first) return valueAtAnchor(0);
    if (frequency >= anchorFrequencies.last) {
      return valueAtAnchor(anchorFrequencies.length - 1);
    }

    for (var i = 1; i < anchorFrequencies.length; i++) {
      final lowerFrequency = anchorFrequencies[i - 1];
      final upperFrequency = anchorFrequencies[i];
      if (frequency <= upperFrequency) {
        final lowerValue = valueAtAnchor(i - 1);
        final upperValue = valueAtAnchor(i);
        final position =
            (math.log(frequency) - math.log(lowerFrequency)) /
            (math.log(upperFrequency) - math.log(lowerFrequency));
        return lowerValue + (upperValue - lowerValue) * position;
      }
    }
    return valueAtAnchor(anchorFrequencies.length - 1);
  }

  void dispose() {
    _disposed = true;
    unawaited(_releaseNative());
  }
}
