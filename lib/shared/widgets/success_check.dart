import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';

/// The success moment: a ring closes, a check strokes itself in, and one halo
/// leaves the badge.
///
/// This is the only place in HozaSend allowed a flourish, and it earns it - it
/// is the single frame the whole product exists for, and a drawn check reads as
/// "this just finished" in a way a static tick never does. It plays once, takes
/// well under a second, and blocks nothing: the buttons under it are live the
/// entire time.
class HozaSuccessCheck extends StatefulWidget {
  const HozaSuccessCheck({
    super.key,
    this.size = 92,
    this.color,
    this.background,
  });

  final double size;

  /// Defaults to the success colour. Failure uses [SheetBadge] instead - a
  /// drawn animation would celebrate the wrong thing.
  final Color? color;
  final Color? background;

  @override
  State<HozaSuccessCheck> createState() => _HozaSuccessCheckState();
}

class _HozaSuccessCheckState extends State<HozaSuccessCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final Color tick = widget.color ?? c.success;
    final Color halo = widget.background ?? c.successSoft;

    // Reduced motion still gets the badge, just already finished.
    if (context.reduceMotion) {
      return _Badge(size: widget.size, tick: tick, halo: halo, progress: 1);
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) => _Badge(
          size: widget.size,
          tick: tick,
          halo: halo,
          progress: _controller.value,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.size,
    required this.tick,
    required this.halo,
    required this.progress,
  });

  final double size;
  final Color tick;
  final Color halo;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SuccessPainter(progress: progress, tick: tick, halo: halo),
    );
  }
}

class _SuccessPainter extends CustomPainter {
  const _SuccessPainter({
    required this.progress,
    required this.tick,
    required this.halo,
  });

  /// 0 to 1, once.
  final double progress;
  final Color tick;
  final Color halo;

  /// Slices the single timeline into overlapping stages, so the check starts
  /// before the ring has finished closing and the whole thing stays under a
  /// second without any stage feeling rushed.
  static double _stage(double t, double begin, double end) =>
      ((t - begin) / (end - begin)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);
    final double radius = size.width / 2;
    final double stroke = size.width * 0.075;

    canvas.drawCircle(centre, radius * 0.92, Paint()..color = halo);

    // The ring closes clockwise from the top.
    final double ring = Curves.easeOutCubic.transform(_stage(progress, 0, 0.55));
    if (ring > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius - stroke / 2),
        -math.pi / 2,
        math.pi * 2 * ring,
        false,
        Paint()
          ..color = tick.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.55
          ..strokeCap = StrokeCap.round,
      );
    }

    // One halo leaving the badge, at the moment the check lands.
    final double pulse = _stage(progress, 0.5, 1.0);
    if (pulse > 0 && pulse < 1) {
      canvas.drawCircle(
        centre,
        radius * (0.92 + 0.42 * Curves.easeOutCubic.transform(pulse)),
        Paint()
          ..color = tick.withValues(alpha: 0.30 * (1 - pulse))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // The check itself, drawn along its own path rather than faded in.
    final double draw = Curves.easeOutCubic.transform(_stage(progress, 0.32, 0.9));
    if (draw <= 0) return;

    final Path path = Path()
      ..moveTo(size.width * 0.29, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.67)
      ..lineTo(size.width * 0.72, size.height * 0.36);

    final Paint pen = Paint()
      ..color = tick
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final PathMetric metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * draw), pen);
    }
  }

  @override
  bool shouldRepaint(_SuccessPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.tick != tick ||
      oldDelegate.halo != halo;
}
