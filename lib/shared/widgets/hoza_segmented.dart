import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import 'hoza_buttons.dart';

/// One option inside a [HozaSegmented].
class SegmentOption<T> {
  const SegmentOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// A compact segmented control, used for the Appearance choice.
///
/// Segments share the width equally, so the selected indicator can simply
/// slide between them: one surface that travels, rather than one fading out
/// while another fades in. The movement is the feedback - it shows which way
/// the choice went, which a cross-fade cannot.
class HozaSegmented<T> extends StatelessWidget {
  const HozaSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final int index = options.indexWhere(
      (SegmentOption<T> o) => o.value == selected,
    );

    return Container(
      padding: const EdgeInsets.all(Insets.xs),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      child: Stack(
        children: <Widget>[
          if (index >= 0 && options.length > 1)
            Positioned.fill(
              child: AnimatedAlign(
                duration: context.motion(Motion.normal),
                curve: Motion.emphasized,
                alignment: Alignment(-1 + 2 * index / (options.length - 1), 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / options.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(color: c.borderStrong),
                    ),
                  ),
                ),
              ),
            ),
          Row(
            children: options.map((SegmentOption<T> option) {
              final bool active = option.value == selected;
              return Expanded(
                // The same press, cursor, focus ring and haptic as every other
                // control, so a segment is not a special case the hand has to
                // learn separately.
                child: PressableScale(
                  onTap: active ? null : () => onChanged(option.value),
                  scale: 0.96,
                  hoverScale: 1,
                  focusRadius: Radii.sm,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Insets.md),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        if (option.icon != null) ...<Widget>[
                          // The colours cross-fade while the surface slides,
                          // so the label arrives lit rather than switching.
                          TweenAnimationBuilder<Color?>(
                            tween: ColorTween(
                              end: active ? c.primary : c.textTertiary,
                            ),
                            duration: context.motion(Motion.normal),
                            curve: Motion.standard,
                            builder:
                                (
                                  BuildContext context,
                                  Color? colour,
                                  Widget? child,
                                ) => Icon(option.icon, size: 16, color: colour),
                          ),
                          const SizedBox(width: Insets.sm),
                        ],
                        Flexible(
                          child: AnimatedDefaultTextStyle(
                            duration: context.motion(Motion.normal),
                            curve: Motion.standard,
                            style:
                                context.text.bodyMedium?.copyWith(
                                  color: active
                                      ? c.textPrimary
                                      : c.textSecondary,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ) ??
                                const TextStyle(),
                            child: Text(
                              option.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
