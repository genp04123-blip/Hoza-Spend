import 'package:flutter/material.dart';

/// The gold ramp: the one warm colour HozaSend spends.
///
/// Kept in a single place because the wordmark shimmer and the light behind the
/// top of the home page have to be the same gold - two golds a few degrees
/// apart read as a mistake, not as a palette.
///
/// Each tone comes in a dark-theme and a light-theme value. The dark values
/// over a near-white page would leave the mark barely there, so light takes the
/// whole ramp down a few stops rather than reusing it.
class HozaGold {
  const HozaGold._();

  /// Antique gold. The edge of a letter, so it keeps an outline.
  static const Color deepDark = Color(0xFF8A5A12);

  /// The body of the gold - what most of the surface is at any moment.
  static const Color midDark = Color(0xFFE3B84F);

  /// The specular peak, near-white, where the travelling light is.
  static const Color peakDark = Color(0xFFFFF3C8);

  static const Color deepLight = Color(0xFF6E4A0E);
  static const Color midLight = Color(0xFFB0801C);
  static const Color peakLight = Color(0xFFE7C258);

  /// The wide, low-alpha wash thrown behind the header. Deliberately faint:
  /// this is the light in the room, not a shape anyone should be able to point
  /// at.
  static const Color _auraDark = Color(0x3AE3B84F);
  static const Color _emberDark = Color(0x28FFC96B);
  static const Color _auraLight = Color(0x22C08A1E);
  static const Color _emberLight = Color(0x18E7C258);

  static Color aura(Brightness brightness) =>
      brightness == Brightness.dark ? _auraDark : _auraLight;

  static Color ember(Brightness brightness) =>
      brightness == Brightness.dark ? _emberDark : _emberLight;

  /// The body tone for a brightness. For gold that has to sit on a surface -
  /// an edge, a rule - rather than fill letters.
  static Color mid(Brightness brightness) =>
      brightness == Brightness.dark ? midDark : midLight;
}
