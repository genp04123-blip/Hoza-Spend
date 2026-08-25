import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';

/// The transfer progress bar.
///
/// The fill is animated between values rather than snapped, so the ten updates
/// a second read as one smooth movement instead of a flicker. The animation is
/// shorter than the update interval, so it always settles before the next
/// value arrives and can never lag behind the real figure.
///
/// While [active], a slow band of light travels along the filled part. That is
/// the one thing a progress bar cannot otherwise say: a large file can sit on
/// the same percentage for a while, and a still bar at that moment looks
/// stalled even though nothing is wrong.
class HozaProgressBar extends StatefulWidget {
  const HozaProgressBar({
    super.key,
    required this.value,
    this.height = 10,
    this.color,
    this.active = false,
  });

  /// 0.0 to 1.0.
  final double value;
  final double height;

  /// Overrides the brand gradient with a flat colour, for success and failure.
  final Color? color;

  /// True only while bytes are actually moving.
  final bool active;

  @override
  State<HozaProgressBar> createState() => _HozaProgressBarState();
}

class _HozaProgressBarState extends State<HozaProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );

  bool get _shouldRun => widget.active && !context.reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(HozaProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) _sync();
  }

  void _sync() {
    if (_shouldRun) {
      if (!_sheen.isAnimating) _sheen.repeat();
    } else {
      _sheen.stop();
    }
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.pill),
      child: Container(
        height: widget.height,
        color: c.surfaceMuted,
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: widget.value.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 110),
            curve: Curves.linear,
            builder: (BuildContext context, double shown, Widget? child) {
              return FractionallySizedBox(
                widthFactor: shown,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: widget.color == null ? c.brandGradient : null,
                    color: widget.color,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  // Clipped to the filled part, so nothing here ever appears
                  // over track that has not been earned yet.
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        if (_shouldRun) _Sheen(animation: _sheen),
                        // The head: a bright cap riding the leading edge. It
                        // is what makes the bar read as being pushed forward
                        // rather than redrawn a little longer each time, and
                        // it retires at 100% so the finished bar sits flat.
                        if (widget.active && shown > 0.004 && shown < 0.999)
                          Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              width: widget.height * 0.85,
                              height: double.infinity,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  borderRadius:
                                      BorderRadius.circular(Radii.pill),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color:
                                          Colors.white.withValues(alpha: 0.45),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A soft band of light sweeping left to right, forever.
class _Sheen extends StatelessWidget {
  const _Sheen({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        return FractionallySizedBox(
          widthFactor: 0.32,
          // Travels from just off the left edge to just off the right.
          alignment: Alignment(-1 + 2.6 * animation.value, 0),
          child: child,
        );
      },
      child: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0x00FFFFFF),
              Color(0x38FFFFFF),
              Color(0x00FFFFFF),
            ],
          ),
        ),
      ),
    );
  }
}
