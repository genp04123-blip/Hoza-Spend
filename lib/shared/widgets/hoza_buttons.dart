import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import 'edge_light.dart';

/// Wraps a child so it responds to every way a person can reach it: it dips
/// under a finger, lifts under a cursor, and shows a ring when it is the
/// keyboard's target. The whole app uses this rather than per-button animation
/// code, so every tap feels the same.
///
/// The lift is what makes the Windows build feel native; the dip and the short
/// haptic are what make the Android build feel physical.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.hoverScale = 1.012,
    this.haptic = true,
    this.focusRadius = Radii.md,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// How far the child dips while held.
  final double scale;

  /// How far it lifts under a cursor. Desktop only in practice - a touch
  /// device never reports hover.
  final double hoverScale;

  /// Fires a light tick on press. Off for anything that repeats quickly.
  final bool haptic;

  /// Corner radius of the keyboard focus ring, matched to the child's own.
  final double focusRadius;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;
  bool _hovered = false;
  bool _focused = false;

  bool get _enabled => widget.onTap != null;

  void _set(void Function() change) {
    if (!_enabled) return;
    setState(change);
  }

  void _press(bool value) {
    if (!_enabled || _down == value) return;
    if (value && widget.haptic) {
      // Only where a device can actually tick. On desktop the channel is not
      // implemented, and calling it would raise for nothing.
      final TargetPlatform platform = Theme.of(context).platform;
      if (platform == TargetPlatform.android ||
          platform == TargetPlatform.iOS) {
        HapticFeedback.selectionClick();
      }
    }
    setState(() => _down = value);
  }

  double get _targetScale {
    if (!_enabled) return 1;
    if (_down) return widget.scale;
    if (_hovered) return widget.hoverScale;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    // Down fast and linear-ish, back up slower with a hair of overshoot. The
    // asymmetry is the whole trick: a press that returns at the same speed it
    // left reads as a picture changing, not as a surface being pushed.
    final Widget scaled = AnimatedScale(
      scale: _targetScale,
      duration: context.motion(_down ? Motion.press : Motion.release),
      curve: _down ? Motion.standard : Motion.settle,
      child: widget.child,
    );

    return FocusableActionDetector(
      enabled: _enabled,
      mouseCursor:
          _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowHoverHighlight: (bool value) => _set(() => _hovered = value),
      onShowFocusHighlight: (bool value) => _set(() => _focused = value),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          // Passthrough so a wrapped card still receives the exact constraints
          // it had before, and no clipping so the hover lift is not shaved off
          // at the edges.
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: <Widget>[
            scaled,
            // Drawn over the child rather than around it, so gaining focus
            // never changes the layout by a pixel.
            if (_focused)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(widget.focusRadius + 3),
                      border: Border.all(color: c.accent, width: 2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The main call to action: gradient fill, full width by default.
///
/// Hovering warms the shadow into a brand glow instead of only moving the
/// button, which is what separates a real primary action from a coloured box.
class HozaPrimaryButton extends StatefulWidget {
  const HozaPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.expand = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expand;

  @override
  State<HozaPrimaryButton> createState() => _HozaPrimaryButtonState();
}

class _HozaPrimaryButtonState extends State<HozaPrimaryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool enabled = widget.onPressed != null;
    final Color foreground = enabled ? c.onBrand : c.textTertiary;

    final Widget content = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // The lit rim, and one soft lap of light around it. This is the screen's
      // live action, and the edge is where that can be said without adding a
      // single pixel of chrome inside the button.
      child: EdgeLight(
        radius: Radii.md,
        active: enabled,
        color: c.onBrand,
        rim: c.onBrand.withValues(alpha: 0.30),
        width: 1.5,
        intensity: enabled ? (_hovered ? 1 : 0.9) : 0,
        // Animated so enabling a button - the moment a file finally gets
        // picked - reads as the button waking up rather than swapping.
        child: AnimatedContainer(
          duration: context.motion(Motion.normal),
          curve: Motion.standard,
          height: 56,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: Insets.xxl),
          decoration: BoxDecoration(
            gradient: enabled ? c.brandGradient : null,
            color: enabled ? null : c.surfaceMuted,
            borderRadius: BorderRadius.circular(Radii.md),
            boxShadow: !enabled
                ? null
                : (_hovered
                    ? <BoxShadow>[
                        BoxShadow(
                          color: c.primary.withValues(alpha: 0.34),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : c.softShadow),
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (widget.icon != null) ...<Widget>[
                AnimatedSlide(
                  duration: context.motion(Motion.normal),
                  curve: Motion.standard,
                  // A couple of pixels of travel on hover: enough to read as
                  // "this goes somewhere", not enough to notice as movement.
                  offset:
                      _hovered && enabled ? const Offset(0.12, 0) : Offset.zero,
                  child: Icon(widget.icon, size: 20, color: foreground),
                ),
                const SizedBox(width: Insets.md),
              ],
              AnimatedDefaultTextStyle(
                duration: context.motion(Motion.normal),
                curve: Motion.standard,
                style: context.text.labelLarge?.copyWith(color: foreground) ??
                    TextStyle(color: foreground),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );

    return PressableScale(onTap: widget.onPressed, child: content);
  }
}

/// How a button's edge light should read.
///
/// Colour, pace and direction together: three buttons all lit the same way say
/// nothing about which is which, so a control that is a different kind of thing
/// gets a different light rather than a different size alone.
class ButtonEdge {
  const ButtonEdge({required this.color, this.period, this.reverse = false});

  final Color color;

  /// One lap. Null keeps the secondary button's own pace.
  final Duration? period;

  /// Sends the light round the other way.
  final bool reverse;
}

/// Quieter companion to [HozaPrimaryButton]: outlined, same footprint.
class HozaSecondaryButton extends StatefulWidget {
  const HozaSecondaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.expand = true,
    this.compact = false,
    this.edge,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expand;

  /// A shorter, lighter version for actions that are real but not the reason
  /// the screen exists. Same shape, less of it.
  final bool compact;

  /// Overrides the edge light. Given a colour and a pace of its own, a button
  /// stops looking like a copy of the one above it.
  final ButtonEdge? edge;

  @override
  State<HozaSecondaryButton> createState() => _HozaSecondaryButtonState();
}

class _HozaSecondaryButtonState extends State<HozaSecondaryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool enabled = widget.onPressed != null;
    final Color foreground = enabled ? c.textPrimary : c.textTertiary;
    final bool small = widget.compact;
    final ButtonEdge edge = widget.edge ?? ButtonEdge(color: c.accent);

    return PressableScale(
      onTap: widget.onPressed,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        // The same edge language as the primary button, at roughly half the
        // strength and a longer lap: present, but never competing with the
        // action it sits next to.
        child: EdgeLight(
          radius: Radii.md,
          active: enabled,
          color: edge.color,
          intensity: enabled ? (_hovered ? 1 : 0.7) : 0,
          duration: edge.period ?? Motion.edge * 1.45,
          reverse: edge.reverse,
          child: AnimatedContainer(
            duration: context.motion(Motion.fast),
            curve: Motion.standard,
            height: small ? 44 : 56,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(
              horizontal: small ? Insets.lg : Insets.xxl,
            ),
            decoration: BoxDecoration(
              color: _hovered && enabled ? c.surfaceElevated : c.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color: _hovered && enabled ? c.borderStrong : c.border,
              ),
            ),
            child: Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (widget.icon != null) ...<Widget>[
                  AnimatedSlide(
                    duration: context.motion(Motion.normal),
                    curve: Motion.standard,
                    offset: _hovered && enabled
                        ? const Offset(0.12, 0)
                        : Offset.zero,
                    child: Icon(
                      widget.icon,
                      size: small ? 17 : 20,
                      color: foreground,
                    ),
                  ),
                  SizedBox(width: small ? Insets.sm : Insets.md),
                ],
                AnimatedDefaultTextStyle(
                  duration: context.motion(Motion.fast),
                  curve: Motion.standard,
                  style: (small
                          ? context.text.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: foreground,
                            )
                          : context.text.labelLarge
                              ?.copyWith(color: foreground)) ??
                      TextStyle(color: foreground),
                  child: Text(widget.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
