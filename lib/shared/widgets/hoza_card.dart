import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import 'hoza_buttons.dart';

/// The standard HozaSend surface: large radius, hairline border, soft shadow.
///
/// Everything that sits above the page background uses this, so cards never
/// drift apart visually between screens. When [onTap] is given the card also
/// reacts to hover, which is what makes the Windows build feel native.
class HozaCard extends StatefulWidget {
  const HozaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.lg),
    this.onTap,
    this.selected = false,
    this.accentBorder,
    this.radius = Radii.lg,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Corner radius. Slim list rows pass a smaller one - the full radius on a
  /// short row rounds it almost to a pill and loses the sense of a surface.
  final double radius;

  /// Draws the card in its selected state: brand border and tinted fill.
  final bool selected;

  /// Overrides the border colour, for status-carrying cards such as a failed
  /// transfer.
  final Color? accentBorder;

  @override
  State<HozaCard> createState() => _HozaCardState();
}

class _HozaCardState extends State<HozaCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool interactive = widget.onTap != null;
    final Color border = widget.accentBorder ??
        (widget.selected
            ? c.primary
            : (_hovered && interactive ? c.borderStrong : c.border));

    final Widget surface = AnimatedContainer(
      duration: context.motion(Motion.fast),
      curve: Motion.standard,
      padding: widget.padding,
      decoration: BoxDecoration(
        gradient: widget.selected ? null : c.surfaceGradient,
        color: widget.selected ? c.primarySoft : null,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: border, width: widget.selected ? 1.4 : 1),
        boxShadow: _hovered && interactive ? c.liftedShadow : c.softShadow,
      ),
      child: widget.child,
    );

    if (!interactive) return surface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // A card that can be tapped is a button, so it dips like one - less than
      // a real button, because it is a far larger surface and the same
      // percentage would look like a lurch. The cursor, the keyboard ring and
      // the press haptic all come from [PressableScale] too, so a device row
      // behaves exactly like Send does.
      child: PressableScale(
        onTap: widget.onTap,
        scale: 0.985,
        hoverScale: 1,
        focusRadius: widget.radius,
        child: surface,
      ),
    );
  }
}
