import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';

/// One pairing HozaSend can move files between.
///
/// The set matters more than any single entry. People arrive assuming a
/// transfer app is phone-to-phone only, or phone-to-computer only, and never
/// try the third - so the three are always shown together, in the same order,
/// on home and in the intro.
class TransferMode {
  const TransferMode({
    required this.from,
    required this.to,
    required this.label,
  });

  /// The device the files leave.
  final IconData from;

  /// The device they arrive on.
  final IconData to;

  /// Read the way the icons are read, left to right: "phone to phone".
  final String label;

  static const IconData phoneIcon = Icons.smartphone_rounded;
  static const IconData computerIcon = Icons.laptop_rounded;

  static const TransferMode phoneToPhone = TransferMode(
    from: phoneIcon,
    to: phoneIcon,
    label: 'Phone to phone',
  );

  static const TransferMode phoneToComputer = TransferMode(
    from: phoneIcon,
    to: computerIcon,
    label: 'Phone to Windows',
  );

  static const TransferMode computerToComputer = TransferMode(
    from: computerIcon,
    to: computerIcon,
    label: 'Windows to Windows',
  );

  /// Phone-to-phone first: it is the one users doubt most, and the one the
  /// app is least often assumed to do.
  static const List<TransferMode> all = <TransferMode>[
    phoneToPhone,
    phoneToComputer,
    computerToComputer,
  ];
}

/// The three pairings as a compact, quiet row.
///
/// Picture first, words under it. The icons say it faster than a sentence can,
/// and the labels are there for anyone who needs the sentence anyway - screen
/// readers included, which is why each pair is announced as one phrase rather
/// than as two unrelated icons.
class TransferModes extends StatelessWidget {
  const TransferModes({
    super.key,
    this.title = 'Works both ways between any two',
  });

  /// A quiet line above the row. Pass null to show the row alone.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Column(
      children: <Widget>[
        if (title != null) ...<Widget>[
          Text(
            title!,
            textAlign: TextAlign.center,
            style: context.text.labelSmall?.copyWith(color: c.textTertiary),
          ),
          const SizedBox(height: Insets.md),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final TransferMode mode in TransferMode.all)
              Flexible(child: _ModeTile(mode: mode)),
          ],
        ),
      ],
    );
  }
}

/// One pairing: two device tiles with the two-way link drawn between them, and
/// the pair named underneath.
///
/// The devices are given the same small raised tile the intro uses, rather than
/// bare glyphs in a pill. At this size that is what separates "two devices with
/// something between them" from "a row of three icons": the tiles read as
/// objects, and the link reads as the thing joining them.
class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.mode});

  final TransferMode mode;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Semantics(
      label: '${mode.label}, both ways',
      // The icons already carry the meaning; announcing them one by one would
      // only say "smartphone, laptop".
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Scales down rather than overflowing when a very narrow screen or a
          // large text scale leaves less room than the group's natural width.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _DeviceTile(icon: mode.from),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: _BothWays(),
                ),
                _DeviceTile(icon: mode.to),
              ],
            ),
          ),
          const SizedBox(height: Insets.sm),
          Text(
            mode.label,
            textAlign: TextAlign.center,
            style: context.text.labelSmall?.copyWith(color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// One device: a small raised tile with its glyph, matched to the chips on the
/// intro page so the same idea is drawn the same way in both places.
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        gradient: c.surfaceGradient,
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: c.border),
      ),
      child: Icon(icon, size: 16, color: c.primary),
    );
  }
}

/// The link between two devices: two lines, one going each way.
///
/// Drawn rather than assembled from two arrow glyphs. A Material arrow carries
/// its own padding, which forced the two lines apart and left them reading as
/// two separate arrows that happened to be stacked; painted, they sit a few
/// pixels apart and read as one two-way link - which is the point, because
/// either side of every pair here can send and either can receive.
class _BothWays extends StatelessWidget {
  const _BothWays();

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return CustomPaint(
      size: const Size(20, 14),
      painter: _BothWaysPainter(out: c.primary, back: c.accent),
    );
  }
}

class _BothWaysPainter extends CustomPainter {
  const _BothWaysPainter({required this.out, required this.back});

  /// The line leaving the left device.
  final Color out;

  /// The one coming back to it. A second colour, because "both ways" is two
  /// things happening, not one thicker arrow.
  final Color back;

  /// How far apart the two lines sit. Tight on purpose: any wider and they
  /// stop being a pair.
  static const double _gap = 4.4;
  static const double _stroke = 1.6;

  /// Length of each arrowhead arm.
  static const double _head = 3.2;

  @override
  void paint(Canvas canvas, Size size) {
    // Inset so the round caps and the heads stay inside the painted box.
    final double left = _stroke / 2;
    final double right = size.width - _stroke / 2;
    final double middle = size.height / 2;

    final Paint paint = Paint()
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..color = out;

    final double top = middle - _gap / 2;
    canvas.drawLine(Offset(left, top), Offset(right, top), paint);
    canvas.drawPath(
      Path()
        ..moveTo(right - _head, top - _head)
        ..lineTo(right, top)
        ..lineTo(right - _head, top + _head),
      paint,
    );

    final double bottom = middle + _gap / 2;
    paint.color = back;
    canvas.drawLine(Offset(left, bottom), Offset(right, bottom), paint);
    canvas.drawPath(
      Path()
        ..moveTo(left + _head, bottom - _head)
        ..lineTo(left, bottom)
        ..lineTo(left + _head, bottom + _head),
      paint,
    );
  }

  @override
  bool shouldRepaint(_BothWaysPainter oldDelegate) =>
      oldDelegate.out != out || oldDelegate.back != back;
}
