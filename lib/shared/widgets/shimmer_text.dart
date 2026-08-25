import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/sheen.dart';

/// Text cast in light blue, with the light moving across it.
///
/// The letters are filled with a blue ramp - deep at the edges, bright through
/// the middle, with one narrow specular band - and that ramp travels slowly
/// along the word. Most of the wordmark is solid blue at any moment; what moves
/// is the highlight, the way it would on a polished surface catching a light.
///
/// Two things keep it from reading as a screensaver. The bright band is narrow,
/// so it crosses rather than fills; and the pass is slow, because a quick sweep
/// is a loading indicator and this is not asking anyone to wait.
///
/// Reserved for the top of the home page - the wordmark and the headline
/// under it. The lit blue means "this is the product" here; spend it further
/// down the page and it stops meaning anything.
class ShimmerText extends StatefulWidget {
  const ShimmerText(
    this.text, {
    super.key,
    this.style,
    this.intensity = 1,
    this.period = const Duration(milliseconds: 4200),
    this.textAlign,
    this.brightness,
  });

  final String text;
  final TextStyle? style;

  /// How far the letters travel from their normal colour towards the full
  /// ramp, 0 to 1. This is the knob to turn if the blue is too much or too
  /// little.
  final double intensity;

  /// One full pass of the highlight.
  final Duration period;

  final TextAlign? textAlign;

  /// Which half of the ramp to use, when the page it sits on does not follow
  /// the theme. The launch screen is pale whatever the system setting says, and
  /// the dark ramp over it would wash the word out. Defaults to the theme.
  final Brightness? brightness;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  /// The dark theme ramp. Deep blue at the edges so the letters keep an
  /// outline, light blue through the body, near-white at the specular peak.
  static const Color _deepDark = HozaSheen.deepDark;
  static const Color _midDark = HozaSheen.midDark;
  static const Color _peakDark = HozaSheen.peakDark;

  /// Light theme takes the whole ramp down a few stops. The same colours over
  /// white would leave the word barely there.
  static const Color _deepLight = HozaSheen.deepLight;
  static const Color _midLight = HozaSheen.midLight;
  static const Color _peakLight = HozaSheen.peakLight;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  /// The colour stays either way - it is the brand, not the animation. Only
  /// the travelling light stops.
  bool get _shouldRun => !context.reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ShimmerText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.period != oldWidget.period) _controller.duration = widget.period;
  }

  void _sync() {
    if (_shouldRun) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      // Parked a third of the way in, so the still version still shows the
      // highlight somewhere on the word rather than off its end.
      _controller.value = 0.33;
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
    final TextStyle style = widget.style ?? DefaultTextStyle.of(context).style;
    final Color base = style.color ?? c.textPrimary;

    final Widget text = Text(
      widget.text,
      textAlign: widget.textAlign,
      style: style.copyWith(color: base),
    );

    final Widget masked = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) => _ramp(bounds, base),
      child: text,
    );

    if (!_shouldRun) return masked;

    return RepaintBoundary(
      // Isolated: this repaints every frame for as long as the screen is up,
      // and without a boundary it would drag its whole parent along with it.
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (Rect bounds) => _ramp(bounds, base),
          child: child,
        ),
        child: text,
      ),
    );
  }

  Shader _ramp(Rect bounds, Color base) {
    final bool dark =
        (widget.brightness ?? Theme.of(context).brightness) == Brightness.dark;
    final double t = widget.intensity.clamp(0.0, 1.0);

    // Blended from the text's own colour, so `intensity` can dial the whole
    // effect back to plain text without touching anything else.
    Color mix(Color tone) => Color.lerp(base, tone, t) ?? tone;

    final Color deep = mix(dark ? _deepDark : _deepLight);
    final Color mid = mix(dark ? _midDark : _midLight);
    final Color peak = mix(dark ? _peakDark : _peakLight);

    return LinearGradient(
      // Diagonal, so the light crosses the letters at an angle rather than
      // sliding along them - that reads as a surface being lit, not as a bar
      // moving past.
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[deep, mid, mid, peak, mid, mid, deep],
      stops: const <double>[0, 0.18, 0.42, 0.5, 0.58, 0.82, 1],
      // The ramp starts and ends on the same colour, so tiling it and sliding
      // it by exactly one width loops with no seam.
      tileMode: TileMode.repeated,
      transform: _Slide(_controller.value),
    ).createShader(bounds);
  }
}

/// Slides a gradient along its own axis, one full tile per cycle.
///
/// The offset follows the bounds diagonal rather than only its width, because
/// the ramp above runs corner to corner: translating by (w, h) moves it exactly
/// one period along that axis, which is what lets the repeated tiling loop with
/// no jump at the wrap.
class _Slide extends GradientTransform {
  const _Slide(this.fraction);

  final double fraction;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(
        bounds.width * fraction,
        bounds.height * fraction,
        0,
      );
}
