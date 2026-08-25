import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';

/// Entrance animation used across the app: a short fade with a small rise.
///
/// [index] staggers siblings by [Motion.stagger], which is how device rows and
/// file cards appear one after another instead of all at once. Runs exactly
/// once per mount, so scrolling never re-triggers it.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 14,
  });

  final Widget child;
  final int index;

  /// Vertical travel in logical pixels. Small on purpose.
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.normal,
  );

  @override
  void initState() {
    super.initState();
    final Duration delay = Motion.stagger * widget.index;
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // With motion reduced the content still has to appear - it just appears,
    // without the rise or the stagger before it.
    if (context.reduceMotion) return widget.child;

    final Animation<double> curved = CurvedAnimation(
      parent: _controller,
      curve: Motion.standard,
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (BuildContext context, Widget? child) {
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - curved.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
