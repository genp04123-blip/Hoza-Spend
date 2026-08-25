import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/sheen.dart';
import '../../../shared/widgets/sheen_aura.dart';

/// The backdrop for the first run: a deep page with light blue falling across
/// the top of it.
///
/// Only the intro and the naming screen use this. They are the two screens a
/// person sees before the app has done anything for them, so they are the one
/// place worth spending light - everywhere else the page steps back and lets
/// the devices and the files be the subject.
///
/// Three layers, all flat gradients and no blur filter: a vertical wash that
/// lifts the top of the page towards blue, a wide glow centred above the
/// content, and the same slow drifting lights the home header uses, so the
/// first screen and the home screen are visibly the same product.
class IntroBackdrop extends StatelessWidget {
  const IntroBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final Brightness brightness = Theme.of(context).brightness;

    // Mixed from the page colour rather than picked separately, so the tint
    // sits on the palette instead of next to it - and so it works in both
    // themes without a second set of values.
    final Color crest =
        Color.lerp(c.background, HozaSheen.mid(brightness), 0.16) ??
            c.background;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // Held near the page colour for the bottom half: the light is
          // meant to come from above, and a gradient that runs the whole
          // height reads as a background image rather than as lighting.
          colors: <Color>[crest, c.background, c.background],
          stops: const <double>[0.0, 0.52, 1.0],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            // High and centred, above where the illustration sits.
            center: const Alignment(0, -0.75),
            radius: 1.2,
            colors: <Color>[
              HozaSheen.aura(brightness),
              Colors.transparent,
            ],
          ),
        ),
        child: SheenAura(child: child),
      ),
    );
  }
}
