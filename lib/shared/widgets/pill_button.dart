import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import 'hoza_buttons.dart';

/// A small action that lives inside a row or a card: Open, Open folder,
/// Disconnect.
///
/// Not a third button style for its own sake. The full buttons are 56 high and
/// claim a whole line; a bare `TextButton` on a row of text reads as a link
/// someone forgot to style. This is the size in between - a tinted pill that
/// looks like something to press at a glance, in whatever colour the action
/// deserves.
///
/// Give it a [label] and it draws as a pill; leave the label off and it draws
/// as a circle, for an action whose icon says everything.
class PillButton extends StatefulWidget {
  const PillButton({
    super.key,
    required this.icon,
    this.label,
    this.onPressed,
    this.tone,
    this.tooltip,
  });

  final IconData icon;

  /// Null draws the icon alone, in a circle.
  final String? label;

  final VoidCallback? onPressed;

  /// The colour the action carries. Defaults to the brand: use the danger
  /// colour for something that undoes, and a text colour for something quiet.
  final Color? tone;

  /// Worth setting on an icon-only pill, which has nothing else to say what it
  /// does.
  final String? tooltip;

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool enabled = widget.onPressed != null;
    final Color tone = enabled ? (widget.tone ?? c.primary) : c.textTertiary;
    final bool iconOnly = widget.label == null;

    final Widget pill = AnimatedContainer(
      duration: context.motion(Motion.fast),
      curve: Motion.standard,
      padding: iconOnly
          ? const EdgeInsets.all(7)
          : const EdgeInsets.fromLTRB(9, 5, 11, 5),
      decoration: BoxDecoration(
        // Its own colour at low alpha rather than a surface colour: the fill
        // has to belong to the action, or a row of pills all reads the same.
        color: tone.withValues(alpha: _hovered && enabled ? 0.20 : 0.11),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(
          color: tone.withValues(alpha: _hovered && enabled ? 0.55 : 0.26),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(widget.icon, size: 14, color: tone),
          if (widget.label case final String label) ...<Widget>[
            const SizedBox(width: 5),
            Text(
              label,
              style: context.text.labelSmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ],
      ),
    );

    final Widget pressable = PressableScale(
      onTap: widget.onPressed,
      // Tighter than a full button: a 40-pixel pill dipping as far as a 56
      // one reads as wobble rather than as a press.
      scale: 0.94,
      hoverScale: 1.03,
      focusRadius: Radii.pill,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: pill,
      ),
    );

    if (widget.tooltip case final String message) {
      return Tooltip(message: message, child: pressable);
    }
    return pressable;
  }
}
