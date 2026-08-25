import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';

/// The waiting animation on the receive screen.
///
/// Three layers, each saying something slightly different: rings expanding
/// outward read as "announcing myself", a sweep arc circling reads as
/// "listening", and the mark breathing in the middle reads as "still alive".
/// Together they answer the only question a waiting user has - is anything
/// actually happening?
///
/// Painted with strokes and gradients rather than blurs. This runs for minutes
/// at a time while someone stares at it, so it has to stay cheap.
class ReceiveBeacon extends StatefulWidget {
  const ReceiveBeacon({
    super.key,
    this.size = 260,
    this.active = true,
    this.child,
  });

  final double size;

  /// When false everything settles and the tickers stop.
  final bool active;

  final Widget? child;

  @override
  State<ReceiveBeacon> createState() => _ReceiveBeaconState();
}

class _ReceiveBeaconState extends State<ReceiveBeacon>
    with TickerProviderStateMixin {
  /// Deliberately not a multiple of the sweep, so the two never lock into a
  /// repeating pattern the eye can predict.
  late final AnimationController _rings = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  );

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );

  /// Ambient by definition, so a device asking for reduced motion gets the
  /// beacon as a still mark. The screen's own copy still says it is waiting.
  bool get _shouldRun => widget.active && !context.reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ReceiveBeacon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) _sync();
  }

  void _sync() {
    if (_shouldRun) {
      if (!_rings.isAnimating) _rings.repeat();
      if (!_sweep.isAnimating) _sweep.repeat();
    } else {
      _rings.stop();
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _rings.dispose();
    _sweep.dispose();
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
              animation: Listenable.merge(<Listenable>[_rings, _sweep]),
              builder: (BuildContext context, Widget? child) {
                return CustomPaint(
                  size: Size.square(widget.size),
                  painter: _BeaconPainter(
                    ringProgress: _rings.value,
                    sweepProgress: _sweep.value,
                    ring: c.primary,
                    sweep: c.accent,
                    core: c.primarySoft,
                    halo: c.accentSoft,
                  ),
                );
              },
            ),
            if (widget.child != null)
              AnimatedBuilder(
                animation: _rings,
                builder: (BuildContext context, Widget? child) {
                  // A breath, not a pulse. Anything larger turns the mark into
                  // the loudest thing on a screen that is meant to feel calm.
                  final double breath =
                      1 + 0.028 * math.sin(_rings.value * 2 * math.pi);
                  return Transform.scale(scale: breath, child: child);
                },
                child: widget.child,
              ),
          ],
        ),
      ),
    );
  }
}

class _BeaconPainter extends CustomPainter {
  const _BeaconPainter({
    required this.ringProgress,
    required this.sweepProgress,
    required this.ring,
    required this.sweep,
    required this.core,
    required this.halo,
  });

  final double ringProgress;
  final double sweepProgress;
  final Color ring;
  final Color sweep;
  final Color core;
  final Color halo;

  static const int _ringCount = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);
    final double maxRadius = size.width / 2;

    // Two flat discs stand in for a glow. A real blur at this size costs
    // frames on a phone for something barely visible.
    canvas.drawCircle(centre, maxRadius * 0.46, Paint()..color = halo);
    canvas.drawCircle(centre, maxRadius * 0.30, Paint()..color = core);

    for (int i = 0; i < _ringCount; i++) {
      final double t = (ringProgress + i / _ringCount) % 1.0;
      final double radius = maxRadius * (0.30 + 0.70 * t);
      // Eased so rings slow as they widen, the way a real ripple does.
      final double alpha = (1 - t) * (1 - t) * 0.55;
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..color = ring.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    // The listening sweep: a comet of light circling the beacon.
    final Rect orbit = Rect.fromCircle(center: centre, radius: maxRadius * 0.80);
    canvas.drawArc(
      orbit,
      0,
      math.pi * 2,
      false,
      Paint()
        ..shader = SweepGradient(
          colors: <Color>[
            sweep.withValues(alpha: 0),
            sweep.withValues(alpha: 0),
            sweep.withValues(alpha: 0.85),
            sweep.withValues(alpha: 0),
          ],
          stops: const <double>[0.0, 0.62, 0.95, 1.0],
          transform: GradientRotation(sweepProgress * 2 * math.pi),
        ).createShader(orbit)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // A faint full ring underneath, so the orbit still reads as a circle at
    // the point the comet is not lighting.
    canvas.drawCircle(
      centre,
      maxRadius * 0.80,
      Paint()
        ..color = ring.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BeaconPainter oldDelegate) =>
      oldDelegate.ringProgress != ringProgress ||
      oldDelegate.sweepProgress != sweepProgress ||
      oldDelegate.ring != ring ||
      oldDelegate.sweep != sweep;
}
