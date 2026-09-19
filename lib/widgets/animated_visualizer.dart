import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AnimatedVisualizer extends StatefulWidget {
  final bool isPlaying;
  final int barCount;
  final double maxHeight;
  final double barWidth;
  final List<Color>? gradientColors;

  const AnimatedVisualizer({
    super.key,
    required this.isPlaying,
    this.barCount = 18,
    this.maxHeight = 48,
    this.barWidth = 3.5,
    this.gradientColors,
  });

  @override
  State<AnimatedVisualizer> createState() => _AnimatedVisualizerState();
}

class _AnimatedVisualizerState extends State<AnimatedVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _randomFactors = [];
  final Random _random = Random(42);

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < widget.barCount; i++) {
      _randomFactors.add(0.3 + _random.nextDouble() * 0.7);
    }
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AnimatedVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.gradientColors ?? [AppTheme.primary, AppTheme.secondary];

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.bottomCenter,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(widget.barCount, (index) {
              double value;
              if (widget.isPlaying) {
                final phase = (index / widget.barCount) * 2 * pi;
                final t = _controller.value * 2 * pi;
                final wave1 = sin(t * 1.5 + phase);
                final wave2 = cos(t * 2.2 + phase * 1.8);
                value = ((wave1 + wave2) / 2).abs() * _randomFactors[index % _randomFactors.length];
                value = value.clamp(0.15, 1.0);
              } else {
                value = 0.12;
              }

              final height = (value * widget.maxHeight).clamp(4.0, widget.maxHeight);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  width: widget.barWidth,
                  height: height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: colors,
                    ),
                    boxShadow: widget.isPlaying
                        ? [
                            BoxShadow(
                              color: colors.first.withValues(alpha: 0.4),
                              blurRadius: 4,
                              offset: const Offset(0, -2),
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
