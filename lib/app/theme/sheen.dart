import 'package:flutter/material.dart';

/// The light-blue ramp: the colour the top of the home page is lit with.
///
/// Kept in one place for the same reason [HozaViolet] is - the wordmark, the
/// headline and the wash behind them have to be the same blue, and two blues a
/// few degrees apart read as a mistake rather than as a palette.
///
/// This is a *lighter* blue than `AppColors.primary` on purpose. The primary is
/// the colour of things you press; this is the colour of light falling on the
/// header, and a light that matched the buttons would make the header look like
/// a very large button.
///
/// Each tone comes in a dark-theme and a light-theme value. The dark values
/// over a near-white page would leave the mark barely there, so light takes the
/// whole ramp down a few stops rather than reusing it.
class HozaSheen {
  const HozaSheen._();

  /// Deep steel blue. The edge of a letter, so it keeps an outline.
  static const Color deepDark = Color(0xFF1E6FA8);

  /// The body of the blue - what most of the surface is at any moment.
  static const Color midDark = Color(0xFF6FC8F5);

  /// The specular peak, near-white, where the travelling light is.
  static const Color peakDark = Color(0xFFE8F8FF);

  static const Color deepLight = Color(0xFF12557F);
  static const Color midLight = Color(0xFF2E8FC4);
  static const Color peakLight = Color(0xFF9BD6F2);

  /// The wide, low-alpha wash thrown behind the header. Deliberately faint:
  /// this is the light in the room, not a shape anyone should be able to point
  /// at.
  static const Color _auraDark = Color(0x3A6FC8F5);
  static const Color _emberDark = Color(0x2896E4FF);
  static const Color _auraLight = Color(0x222E8FC4);
  static const Color _emberLight = Color(0x189BD6F2);

  static Color aura(Brightness brightness) =>
      brightness == Brightness.dark ? _auraDark : _auraLight;

  static Color ember(Brightness brightness) =>
      brightness == Brightness.dark ? _emberDark : _emberLight;

  /// The body tone for a brightness. For blue that has to sit on a surface -
  /// an edge, a rule - rather than fill letters.
  static Color mid(Brightness brightness) =>
      brightness == Brightness.dark ? midDark : midLight;
}
