import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';

/// Expanding rings behind the logo while HozaSend looks for devices.
///
/// Stroked circles rather than blurred glows: this runs for seconds at a time
/// on a phone, and a blur filter at this size costs real frames. Wrapped in a
/// [RepaintBoundary] so the sweep never repaints the screen behind it.
class RadarPulse extends StatefulWidget {
  const RadarPulse({
    super.key,
    this.size = 168,
    this.active = true,
    this.child,
  });

  final double size;

  /// When false the rings settle and the ticker stops, so an idle screen is
  /// not animating for nothing.
  final bool active;

  final Widget? child;

  @override
  State<RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<RadarPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.ambient,
  );

  /// The sweep is decoration - the copy beside it already says the app is
  /// searching - so a device asking for reduced motion gets the rings standing
  /// still rather than a slower version of them.
  bool get _shouldRun => widget.active && !context.reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(RadarPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) _sync();
  }

  void _sync() {
    if (_shouldRun) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? child) {
                return CustomPaint(
                  size: Size.square(widget.size),
                  painter: _RadarPainter(
                    progress: _controller.value,
                    ring: c.primary,
                    core: c.primarySoft,
                  ),
                );
              },
            ),
            if (widget.child != null) widget.child!,
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({
    required this.progress,
    required this.ring,
    required this.core,
  });

  /// Loops 0 to 1. Each ring is offset within that cycle so they stagger.
  final double progress;
  final Color ring;
  final Color core;

  static const int _ringCount = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);
    final double maxRadius = size.width / 2;

    canvas.drawCircle(
      centre,
      maxRadius * 0.34,
      Paint()..color = core,
    );

    for (int i = 0; i < _ringCount; i++) {
      final double t = (progress + i / _ringCount) % 1.0;
      // Start just outside the core so rings appear to leave it, not the centre.
      final double radius = maxRadius * (0.34 + 0.66 * t);
      // Fade out over the second half only, so a ring is fully visible as it
      // separates and gone by the edge.
      final double alpha = (1 - t) * 0.45;
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..color = ring.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.ring != ring ||
      oldDelegate.core != core;
}
