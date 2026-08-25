import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';

/// How a [StatusPill] should read at a glance.
enum StatusTone { neutral, positive, working, warning, negative }

/// Small tinted pill with a leading dot: network status, device status,
/// transfer outcome. One component for all of them keeps the language
/// consistent across screens.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.pulse = false,
  });

  final String label;
  final StatusTone tone;

  /// Slowly breathes the dot. Use only while something is genuinely ongoing,
  /// such as scanning for devices.
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final (Color dot, Color fill) = switch (tone) {
      StatusTone.neutral => (c.textTertiary, c.surfaceMuted),
      StatusTone.positive => (c.success, c.successSoft),
      StatusTone.working => (c.accent, c.accentSoft),
      StatusTone.warning => (c.warning, c.dangerSoft),
      StatusTone.negative => (c.danger, c.dangerSoft),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.sm,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Dot(color: dot, pulse: pulse),
          const SizedBox(width: Insets.sm),
          Text(
            label,
            style: context.text.bodySmall?.copyWith(
              color: c.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.pulse});

  final Color color;
  final bool pulse;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.ambient,
  );

  bool get _shouldRun => widget.pulse && !context.reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Dot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse != oldWidget.pulse) _sync();
  }

  void _sync() {
    if (_shouldRun) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.pulse) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.35).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: dot,
    );
  }
}
