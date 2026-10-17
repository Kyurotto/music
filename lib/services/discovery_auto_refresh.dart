import 'dart:async';
import 'package:flutter/widgets.dart';

/// Keeps the dashboard discovery rows (Quick Picks, Covers & Remixes,
/// Community Favorites, Trending For You) fresh without any user action.
///
/// * refreshes every [interval] while the dashboard is open,
/// * refreshes when the app returns to the foreground after [staleAfter],
/// * never overlaps two refreshes and never refreshes more often than
///   [minGap] (so a manual pull-to-refresh is not immediately repeated).
class DiscoveryAutoRefresher with WidgetsBindingObserver {
  DiscoveryAutoRefresher({
    required this.onRefresh,
    this.interval = const Duration(minutes: 10),
    this.staleAfter = const Duration(minutes: 5),
    this.minGap = const Duration(minutes: 1),
  });

  /// Called for each automatic refresh. Errors are swallowed.
  final Future<void> Function() onRefresh;
  final Duration interval;
  final Duration staleAfter;
  final Duration minGap;

  Timer? _timer;
  DateTime _lastRefresh = DateTime.now();
  bool _running = false;
  bool _disposed = false;

  void start() {
    if (_disposed || _timer != null) return;
    WidgetsBinding.instance.addObserver(this);
    _lastRefresh = DateTime.now();
    _timer = Timer.periodic(interval, (_) => _run());
  }

  /// Call after a manual refresh so the timer does not repeat it right away.
  void markRefreshed() => _lastRefresh = DateTime.now();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        DateTime.now().difference(_lastRefresh) >= staleAfter) {
      _run();
    }
  }

  Future<void> _run() async {
    if (_disposed || _running) return;
    if (DateTime.now().difference(_lastRefresh) < minGap) return;
    _running = true;
    try {
      await onRefresh();
    } catch (_) {
      // Network hiccups are fine; the next tick tries again.
    } finally {
      _lastRefresh = DateTime.now();
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }
}