import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import 'hoza_buttons.dart';

/// A small raised button with its icon in a coloured badge, and a light that
/// glints across it.
///
/// For the handful of controls that have to be *found* rather than merely
/// offered - the network shortcuts at the foot of home. A tinted pill is the
/// right size for those but the wrong signal: at that scale a tint reads as a
/// status chip, and the people who needed the firewall or the hotspot never
/// discovered they were things to press.
///
/// So it is built like a button and lit like a surface. The badge, the raised
/// fill and the shadow are what make it look pressable standing still; the
/// glint is what stops it reading as a label - a narrow band of light crossing
/// the face, the way one would cross something polished.
///
/// Deliberately not the edge light the full-size buttons carry. That light
/// marks the live action on a screen, and three lit rims at the foot of the
/// page would compete with Send and Receive above them. This one crosses and
/// is gone.
class GlintButton extends StatefulWidget {
  const GlintButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.tone,
    this.tooltip,
    this.period = const Duration(milliseconds: 5200),
    this.phase = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// The colour the action carries, on the badge and in the glint. Defaults to
  /// the brand.
  final Color? tone;

  final String? tooltip;

  /// One pass of the light. Given per call site, because a row of these
  /// glinting in step reads as one animation rather than three buttons.
  final Duration period;

  /// Where in that pass this button starts, 0 to 1. Same reason.
  final double phase;

  @override
  State<GlintButton> createState() => _GlintButtonState();
}

class _GlintButtonState extends State<GlintButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  bool _hovered = false;

  bool get _enabled => widget.onPressed != null;

  /// The button keeps its shape and its badge either way; only the light
  /// stops.
  bool get _shouldRun => _enabled && !context.reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(GlintButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.period != oldWidget.period) _controller.duration = widget.period;
    _sync();
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
    final Color tone = _enabled ? (widget.tone ?? c.primary) : c.textTertiary;
    final bool lit = _hovered && _enabled;

    final Widget face = AnimatedContainer(
      duration: context.motion(Motion.fast),
      curve: Motion.standard,
      height: 38,
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      decoration: BoxDecoration(
        color: lit ? c.surfaceElevated : null,
        gradient: lit ? null : c.surfaceGradient,
        borderRadius: BorderRadius.circular(Radii.pill),
        // The border takes the action's colour under a cursor. It is the
        // cheapest way to say "this one" without moving anything.
        border: Border.all(
          color: lit ? tone.withValues(alpha: 0.55) : c.border,
        ),
        boxShadow: _enabled ? c.softShadow : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnimatedContainer(
            duration: context.motion(Motion.fast),
            curve: Motion.standard,
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: lit ? 0.30 : 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(widget.icon, size: 15, color: tone),
          ),
          const SizedBox(width: Insets.sm),
          Text(
            widget.label,
            style: context.text.labelSmall?.copyWith(
              // The label is ink, not tint. A whole control in one colour is
              // what made the old pills read as status rather than as action.
              color: _enabled ? c.textPrimary : c.textTertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );

    final Widget pressable = PressableScale(
      onTap: widget.onPressed,
      scale: 0.95,
      hoverScale: 1.03,
      focusRadius: Radii.pill,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Stack(
          children: <Widget>[
            face,
            if (_shouldRun)
              Positioned.fill(
                child: IgnorePointer(
                  // Clipped to the shape of the button, so the band ends at
                  // the pill rather than at a rectangle around it. Isolated,
                  // because this repaints for as long as home is on screen.
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (BuildContext context, Widget? child) {
                          return DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: _glint(tone, lit),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (widget.tooltip case final String message) {
      return Tooltip(message: message, child: pressable);
    }
    return pressable;
  }

  /// The band of light, wherever it has got to in this pass.
  ///
  /// Diagonal, so it crosses the face at an angle instead of sliding along it -
  /// the same reason the wordmark's highlight is diagonal. Narrow, so most of
  /// the button is its own colour at any moment and the light is something
  /// happening to it rather than what it is made of.
  LinearGradient _glint(Color tone, bool lit) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final double peak = ((dark ? 0.30 : 0.20) * (lit ? 1.6 : 1.0)).clamp(
      0.0,
      1.0,
    );

    // Starts off one edge and finishes off the other, so there is a pause
    // between passes instead of a band permanently sitting on the button.
    final double centre = -0.5 + 2.0 * ((_controller.value + widget.phase) % 1);

    // Narrow. A wide band stops being a light crossing the button and becomes
    // a gradient the button is painted with.
    const double half = 0.15;

    double stop(double at) => at.clamp(0.0, 1.0);

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        tone.withValues(alpha: 0),
        tone.withValues(alpha: 0),
        tone.withValues(alpha: peak),
        tone.withValues(alpha: 0),
        tone.withValues(alpha: 0),
      ],
      stops: <double>[
        0,
        stop(centre - half),
        stop(centre),
        stop(centre + half),
        1,
      ],
    );
  }
}
