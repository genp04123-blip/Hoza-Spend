import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../shared/widgets/edge_light.dart';
import '../../../shared/widgets/hoza_buttons.dart';

/// The first thing on an empty Send screen: one large target that says drop
/// files here or tap to pick them.
///
/// A dashed outline rather than a solid card, because a dashed edge is the one
/// shape every desktop user already reads as "things go in here" - and on a
/// phone it still reads as an opening rather than a panel. The whole card is
/// the button; a small "Choose files" link inside a big empty box would waste
/// the one gesture the screen exists for.
class ChooseFilesCard extends StatefulWidget {
  const ChooseFilesCard({
    super.key,
    required this.onChoose,
    this.busy = false,
    this.canDrop = false,
  });

  /// Null while the picker is already open, so it cannot be opened twice.
  final VoidCallback? onChoose;

  /// The system picker is open. The card keeps the light running so the wait
  /// is visibly the app's, not a freeze.
  final bool busy;

  /// This platform can take a drag - worth saying, and only true on desktop.
  final bool canDrop;

  @override
  State<ChooseFilesCard> createState() => _ChooseFilesCardState();
}

class _ChooseFilesCardState extends State<ChooseFilesCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool live = _hovered && widget.onChoose != null;

    return PressableScale(
      onTap: widget.onChoose,
      scale: 0.99,
      hoverScale: 1,
      focusRadius: Radii.lg,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: EdgeLight(
          radius: Radii.lg,
          color: c.accent,
          // Off at rest: this card is a destination, not an alarm. It lights
          // when a cursor is over it, and stays lit while the picker is open.
          active: widget.busy || live,
          intensity: widget.busy ? 0.9 : 0.6,
          duration: Motion.edge,
          child: AnimatedContainer(
            duration: context.motion(Motion.fast),
            curve: Motion.standard,
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.xl,
              vertical: Insets.section,
            ),
            decoration: BoxDecoration(
              color: live ? c.primarySoft : c.surface,
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            foregroundDecoration: _DashedBorder(
              color: live || widget.busy ? c.primary : c.borderStrong,
              radius: Radii.lg,
            ),
            child: Column(
              children: <Widget>[
                AnimatedSlide(
                  duration: context.motion(Motion.normal),
                  curve: Motion.standard,
                  // Lifts towards the label, the way a file being taken in
                  // would. Small enough to feel rather than watch.
                  offset: live ? const Offset(0, -0.08) : Offset.zero,
                  child: AnimatedContainer(
                    duration: context.motion(Motion.normal),
                    curve: Motion.standard,
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: live ? c.primary : c.primarySoft,
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Icon(
                      widget.busy
                          ? Icons.hourglass_top_rounded
                          : Icons.file_upload_outlined,
                      size: 26,
                      color: live ? c.onBrand : c.primary,
                    ),
                  ),
                ),
                const SizedBox(height: Insets.lg),
                Text(
                  widget.busy ? 'Opening...' : 'Choose files',
                  style: context.text.titleMedium,
                ),
                const SizedBox(height: Insets.xs),
                Text(
                  widget.canDrop
                      ? 'Drag files onto this window, or tap to browse. '
                          'Photos, videos, documents - as many as you like.'
                      : 'Photos, videos, documents - anything on this device, '
                          'and as many as you like.',
                  textAlign: TextAlign.center,
                  style:
                      context.text.bodySmall?.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashed rounded outline, drawn as a decoration so it costs nothing until
/// the colour changes.
class _DashedBorder extends Decoration {
  const _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DashedBorderPainter(color: color, radius: radius);

  @override
  bool operator ==(Object other) =>
      other is _DashedBorder && other.color == color && other.radius == radius;

  @override
  int get hashCode => Object.hash(color, radius);
}

class _DashedBorderPainter extends BoxPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double _dash = 7;
  static const double _gap = 6;
  static const double _width = 1.4;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final Size size = configuration.size ?? Size.zero;
    if (size.isEmpty) return;

    final Path outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (offset & size).deflate(_width / 2),
          Radius.circular(radius - _width / 2),
        ),
      );

    final Paint pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width
      ..strokeCap = StrokeCap.round;

    for (final PathMetric metric in outline.computeMetrics()) {
      double start = 0;
      while (start < metric.length) {
        canvas.drawPath(
          metric.extractPath(start, start + _dash),
          pen,
        );
        start += _dash + _gap;
      }
    }
  }
}
