import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';

/// A light that travels around the edge of a surface.
///
/// Two parts: a static hairline rim that says where the edge is, and a soft
/// comet that laps it. The comet is drawn with a rotating sweep gradient - one
/// stroke, one shader, no per-frame allocation - because this runs the whole
/// time a screen is open and has to cost nothing on a phone.
///
/// Used to mark which button on a screen is the live one. Deliberately not
/// applied to everything: if every edge moved, none of them would mean
/// anything, and the app would read as neon rather than lit.
class EdgeLight extends StatefulWidget {
  const EdgeLight({
    super.key,
    required this.child,
    required this.radius,
    required this.color,
    this.rim,
    this.active = true,
    this.intensity = 1,
    this.width = 1.3,
    this.duration = Motion.edge,
    this.reverse = false,
  });

  final Widget child;

  /// Corner radius of the surface underneath. Must match, or the light will
  /// cut across its corners.
  final double radius;

  /// The travelling light.
  final Color color;

  /// The hairline that stays. Null leaves the surface's own border to do it.
  final Color? rim;

  /// False parks the light and stops the ticker - a disabled button has
  /// nothing to advertise.
  final bool active;

  /// Scales both parts together, so hover can raise the whole effect without
  /// re-picking colours.
  final double intensity;

  final double width;

  /// One lap. Given per call site so two buttons on the same screen never
  /// fall into lockstep.
  final Duration duration;

  /// Sends the light round the other way. Paired with a different colour and
  /// pace, it is what makes one control's edge read as a different thing from
  /// its neighbour's rather than as the same effect twice.
  final bool reverse;

  @override
  State<EdgeLight> createState() => _EdgeLightState();
}

class _EdgeLightState extends State<EdgeLight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  bool get _shouldRun => widget.active && !context.reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(EdgeLight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
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
    final bool running = _shouldRun;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            foregroundPainter: _EdgePainter(
              // Parked rather than hidden when motion is reduced: the rim
              // still draws, only the lap stops.
              progress: running ? _controller.value : -1,
              radius: widget.radius,
              color: widget.color,
              rim: widget.rim,
              intensity: widget.intensity.clamp(0.0, 1.0),
              width: widget.width,
              reverse: widget.reverse,
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  const _EdgePainter({
    required this.progress,
    required this.radius,
    required this.color,
    required this.rim,
    required this.intensity,
    required this.width,
    required this.reverse,
  });

  /// 0 to 1 for one lap; negative parks the light and draws the rim only.
  final double progress;
  final double radius;
  final Color color;
  final Color? rim;
  final double intensity;
  final double width;
  final bool reverse;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || intensity <= 0) return;

    final RRect edge = RRect.fromRectAndRadius(
      // Inset by half the stroke so the light sits on the edge rather than
      // half outside it, where the corners would look clipped.
      Rect.fromLTWH(0, 0, size.width, size.height).deflate(width / 2),
      Radius.circular(math.max(radius - width / 2, 0)),
    );

    if (rim case final Color hairline) {
      canvas.drawRRect(
        edge,
        Paint()
          ..color = hairline.withValues(
            alpha: hairline.a * intensity,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = width,
      );
    }

    if (progress < 0) return;

    // A short bright head with a long fade behind it, rotated once per lap.
    final Rect bounds = Offset.zero & size;
    Shader comet(double peak) => SweepGradient(
          colors: <Color>[
            color.withValues(alpha: 0),
            color.withValues(alpha: 0),
            color.withValues(alpha: peak.clamp(0.0, 1.0)),
            color.withValues(alpha: 0),
          ],
          stops: const <double>[0.0, 0.66, 0.95, 1.0],
          transform: GradientRotation(
            (reverse ? -progress : progress) * 2 * math.pi,
          ),
        ).createShader(bounds);

    // Bloom first: the same light, wider and dimmer, spilling to either side
    // of the edge. Two flat strokes read as a glow without a blur filter,
    // which is the one thing here that would cost real frames.
    canvas.drawRRect(
      edge,
      Paint()
        ..shader = comet(0.34 * intensity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 3.6,
    );

    // Then the hot core on top, at full strength.
    canvas.drawRRect(
      edge,
      Paint()
        ..shader = comet(intensity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(_EdgePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.intensity != intensity ||
      oldDelegate.color != color ||
      oldDelegate.rim != rim ||
      oldDelegate.radius != radius ||
      oldDelegate.width != width ||
      oldDelegate.reverse != reverse;
}
