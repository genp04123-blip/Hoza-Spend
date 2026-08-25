import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';

/// The two devices, and the files crossing between them.
///
/// The percentage below answers "how far"; this answers "from where, to where,
/// and is anything actually moving". Packets leave the sender, arc across and
/// land, over and over, for as long as bytes are in flight - the same thing a
/// user leans in to check when a transfer looks stuck.
///
/// One painter, three dots and a dotted baseline. No particles, no blur: this
/// runs for the whole length of a transfer, which is exactly when the UI has
/// the least frame budget to spare.
class TransferFlight extends StatefulWidget {
  const TransferFlight({
    super.key,
    required this.fromLabel,
    required this.toLabel,
    required this.fromIcon,
    required this.toIcon,
    this.active = true,
    this.complete = false,
    this.failed = false,
  });

  /// Always the sender on the left, whichever end this device is.
  final String fromLabel;
  final String toLabel;
  final IconData fromIcon;
  final IconData toIcon;

  /// True while bytes are moving. False parks the packets.
  final bool active;

  /// Landed. The path goes solid and the destination takes a check.
  final bool complete;

  /// Stopped short - cancelled, declined or failed.
  final bool failed;

  @override
  State<TransferFlight> createState() => _TransferFlightState();
}

class _TransferFlightState extends State<TransferFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  bool get _shouldRun =>
      widget.active && !widget.complete && !context.reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(TransferFlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active ||
        widget.complete != oldWidget.complete) {
      _sync();
    }
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
    final Color line = widget.failed
        ? c.danger
        : (widget.complete ? c.success : c.primary);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Endpoint(
          icon: widget.fromIcon,
          label: widget.fromLabel,
          tint: c.primary,
        ),
        Expanded(
          child: Padding(
            // Lines up with the middle of the endpoint tiles above the labels.
            padding: const EdgeInsets.only(top: 14),
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? child) {
                  return CustomPaint(
                    size: const Size(double.infinity, 32),
                    painter: _FlightPainter(
                      progress: _shouldRun ? _controller.value : -1,
                      line: line,
                      complete: widget.complete,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        _Endpoint(
          icon: widget.complete ? Icons.check_rounded : widget.toIcon,
          label: widget.toLabel,
          tint: widget.complete ? c.success : c.accent,
          // Only the receiving end reacts to the landing, so the eye is drawn
          // to where the files ended up.
          pop: widget.complete,
        ),
      ],
    );
  }
}

/// One end of the flight: a tile and the name under it.
class _Endpoint extends StatelessWidget {
  const _Endpoint({
    required this.icon,
    required this.label,
    required this.tint,
    this.pop = false,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final bool pop;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    Widget tile = AnimatedContainer(
      duration: context.motion(Motion.normal),
      curve: Motion.standard,
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tint.withValues(alpha: 0.45)),
      ),
      child: Icon(icon, size: 21, color: tint),
    );

    if (pop && !context.reduceMotion) {
      tile = TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.8, end: 1),
        duration: Motion.slow,
        curve: Motion.emphasized,
        builder: (BuildContext context, double value, Widget? child) =>
            Transform.scale(scale: value, child: child),
        child: tile,
      );
    }

    return SizedBox(
      width: 84,
      child: Column(
        children: <Widget>[
          tile,
          const SizedBox(height: Insets.sm),
          Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall?.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _FlightPainter extends CustomPainter {
  const _FlightPainter({
    required this.progress,
    required this.line,
    required this.complete,
  });

  /// 0 to 1, looping. Negative parks the packets and draws the path only.
  final double progress;
  final Color line;
  final bool complete;

  /// Three in the air at once: one leaving, one crossing, one landing. Fewer
  /// reads as a stutter, more reads as a swarm.
  static const int _packets = 3;

  /// How high the arc rises at its peak.
  static const double _arc = 9;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final double y = size.height / 2;

    // The path itself: dotted while files are still crossing it, solid once
    // they have all landed. The change of state is the point.
    if (complete) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = line.withValues(alpha: 0.55)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    } else {
      const double dash = 5;
      const double gap = 7;
      final Paint pen = Paint()
        ..color = line.withValues(alpha: 0.22)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (double x = 0; x < size.width; x += dash + gap) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + dash, size.width), y),
          pen,
        );
      }
    }

    if (progress < 0 || complete) return;

    for (int i = 0; i < _packets; i++) {
      final double t = (progress + i / _packets) % 1.0;
      // Eased so a packet leaves quickly and settles into its landing, the
      // way a thrown thing does.
      final double x = size.width * Curves.easeInOutSine.transform(t);
      final double lift = _arc * math.sin(t * math.pi);
      // Fades in off the sender and out into the receiver, so nothing ever
      // pops into existence mid-air.
      final double alpha = math.sin(t * math.pi).clamp(0.0, 1.0);

      canvas.drawCircle(
        Offset(x, y - lift),
        3.2,
        Paint()..color = line.withValues(alpha: 0.95 * alpha),
      );
      // A short trail behind it. Two flat dots are cheaper than any blur and
      // read the same at this size.
      canvas.drawCircle(
        Offset(x - 7, y - lift * 0.82),
        2.0,
        Paint()..color = line.withValues(alpha: 0.35 * alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_FlightPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.line != line ||
      oldDelegate.complete != complete;
}
