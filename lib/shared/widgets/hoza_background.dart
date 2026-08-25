import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';

/// The page background, used by every screen.
///
/// Three layers: a vertical fall from a lifted top to the deepest tone, a warm
/// brand light high on the left, and a cooler one low on the right. Lighting a
/// large dark surface from two directions is what stops it reading as black
/// cardboard, and it gives cards something to sit on instead of float against.
///
/// Painted with gradients rather than blurred shapes on purpose. A wide blur
/// filter is expensive on low-end Android and would be running behind every
/// screen in the app, including during a transfer - which is exactly when the
/// UI must not drop frames.
class HozaBackground extends StatelessWidget {
  const HozaBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[c.backgroundTop, c.background],
          // The lift is spent over the top third; below that the page settles
          // so long lists do not slowly brighten as you scroll.
          stops: const <double>[0.0, 0.55],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            // Off-centre and above the top edge, so what lands on screen is
            // the falloff rather than a visible disc.
            center: const Alignment(-0.6, -1.1),
            radius: 1.5,
            colors: <Color>[c.backgroundTint, Colors.transparent],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1.05, 0.85),
              radius: 1.25,
              colors: <Color>[c.backgroundGlow, Colors.transparent],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
