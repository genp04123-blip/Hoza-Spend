import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';

/// The badge that sits at the centre of a radar or beacon.
///
/// Deliberately not the app logo. A mark at the centre of a sweeping animation
/// says "this app", which the user already knows; an icon there should say what
/// the app is *doing* right now - searching, linking, waiting to receive. The
/// logo stays where identity is the point: the header, onboarding and the
/// launcher.
class PulseIcon extends StatelessWidget {
  const PulseIcon({
    super.key,
    required this.icon,
    this.size = 64,
    this.filled = false,
  });

  final IconData icon;
  final double size;

  /// Brand gradient instead of a plain surface. For the one thing on screen
  /// that should draw the eye.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: filled ? c.brandGradient : null,
        color: filled ? null : c.surfaceElevated,
        border: filled ? null : Border.all(color: c.borderStrong),
        boxShadow: c.softShadow,
      ),
      child: Icon(
        icon,
        size: size * 0.44,
        color: filled ? c.onBrand : c.primary,
      ),
    );
  }
}
