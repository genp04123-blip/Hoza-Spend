import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/constants/app_constants.dart';
import 'shimmer_text.dart';

/// The HozaSend mark: a folder with a paper plane leaving it - files, in
/// flight.
///
/// The same artwork the launcher icon is built from, so what the user taps on
/// their home screen is exactly what greets them inside the app.
///
/// The source is opaque - the mark sits on its own white ground - so it is
/// clipped to a rounded tile here. Drawn as-is it would read as a white
/// rectangle stuck on a dark page rather than as an icon.
class HozaLogo extends StatelessWidget {
  const HozaLogo({super.key, this.size = 48});

  static const String assetPath = 'assets/icon/hoza_icon.png';

  /// Fraction of the width the corner radius takes. This is what turns a
  /// square image into an app-icon tile, so it matches the shape the launcher
  /// gives the same artwork.
  static const double _cornerRatio = 0.225;

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * _cornerRatio),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        // Cover, so the tile is always filled edge to edge whatever the
        // source's aspect ratio turns out to be.
        fit: BoxFit.cover,
        // Decoded at display size: the source is 1024px square, and every
        // place this appears is a fraction of that.
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// Mark plus wordmark, as used in the app bar and on the home screen.
class HozaLockup extends StatelessWidget {
  const HozaLockup({super.key, this.markSize = 38, this.showTagline = false});

  final double markSize;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        HozaLogo(size: markSize),
        const SizedBox(width: Insets.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ShimmerText(
              AppConstants.appName,
              style: context.text.headlineSmall?.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            if (showTagline)
              Text(
                AppConstants.tagline,
                style: context.text.bodySmall?.copyWith(color: c.textSecondary),
              ),
          ],
        ),
      ],
    );
  }
}
