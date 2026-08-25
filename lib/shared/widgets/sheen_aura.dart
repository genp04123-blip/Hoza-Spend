import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/sheen.dart';

/// A slow blue light that drifts behind whatever it wraps.
///
/// Used behind the top of the home page, so the mark, the headline and the
/// status pills all sit in the same light instead of the wordmark being the
/// only lit thing up there.
///
/// It never stops. Two soft lights circle on a long period - one wide and
/// open, one smaller and closer on the opposite phase - and their brightness
/// breathes with them. Nothing arrives and nothing finishes, which is what
/// keeps it ambient: a loop with a beginning would ask to be watched.
///
/// Painted as radial gradients, never a blur filter. This runs for as long as
/// home is on screen, and a wide blur behind the whole header is the kind of
/// thing that costs frames on a low-end Android.
class SheenAura extends StatefulWidget {
  const SheenAura({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 12000),
  });

  final Widget child;

  /// One full circuit of both lights.
  final Duration period;

  @override
  State<SheenAura> createState() => _SheenAuraState();
}

class _SheenAuraState extends State<SheenAura>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  /// The colour stays either way - it is the brand, not the animation. Only
  /// the drift stops.
  bool get _shouldRun => !context.reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SheenAura oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.period != oldWidget.period) _controller.duration = widget.period;
  }

  void _sync() {
    if (_shouldRun) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      // Parked where both lights are on screen, so the still version still
      // reads as lit rather than as an unlit corner.
      _controller.value = 0.2;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color aura = HozaSheen.aura(brightness);
    final Color ember = HozaSheen.ember(brightness);

    if (!_shouldRun) {
      return CustomPaint(
        painter: _AuraPainter(t: _controller.value, aura: aura, ember: ember),
        child: widget.child,
      );
    }

    return RepaintBoundary(
      // Isolated: this repaints every frame while home is up, and without a
      // boundary it would drag the whole page along with it.
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) => CustomPaint(
          painter: _AuraPainter(t: _controller.value, aura: aura, ember: ember),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Paints the two lights behind the child.
///
/// Both are allowed to spill outside the header's box - the page padding is
/// inside the same viewport, so letting the falloff run past the text is what
/// stops it reading as a rectangle of glow sitting on the page.
class _AuraPainter extends CustomPainter {
  const _AuraPainter({
    required this.t,
    required this.aura,
    required this.ember,
  });

  final double t;
  final Color aura;
  final Color ember;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final double angle = t * 2 * math.pi;

    _light(
      canvas: canvas,
      size: size,
      centre: Alignment(
        -0.45 + 0.35 * math.sin(angle),
        -0.75 + 0.20 * math.cos(angle),
      ),
      radius: size.width * 0.95,
      // Brightest when the light is high and left, which is where the mark
      // and the headline are.
      colour: _breathe(aura, 0.70 + 0.30 * (0.5 + 0.5 * math.cos(angle))),
    );

    _light(
      canvas: canvas,
      size: size,
      centre: Alignment(
        0.65 - 0.30 * math.sin(angle),
        0.55 - 0.25 * math.cos(angle),
      ),
      radius: size.width * 0.60,
      colour: _breathe(ember, 0.65 + 0.35 * (0.5 + 0.5 * math.sin(angle))),
    );
  }

  void _light({
    required Canvas canvas,
    required Size size,
    required Alignment centre,
    required double radius,
    required Color colour,
  }) {
    final Rect rect = Offset.zero & size;
    final Offset origin = centre.withinRect(rect);
    final Rect circle = Rect.fromCircle(center: origin, radius: radius);
    final Paint paint = Paint()
      ..shader = RadialGradient(
        // Held at full strength through the middle, then a long fall to
        // nothing: a linear ramp leaves a visible edge where it lands.
        colors: <Color>[
          colour,
          colour.withValues(alpha: colour.a * 0.45),
          colour.withValues(alpha: 0),
        ],
        stops: const <double>[0.0, 0.45, 1.0],
      ).createShader(circle);
    canvas.drawCircle(origin, radius, paint);
  }

  Color _breathe(Color colour, double factor) =>
      colour.withValues(alpha: (colour.a * factor).clamp(0.0, 1.0));

  @override
  bool shouldRepaint(_AuraPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.aura != aura ||
      oldDelegate.ember != ember;
}
