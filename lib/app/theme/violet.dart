import 'package:flutter/material.dart';

/// The light purple used for the History edge, and nothing else yet.
///
/// A third accent needs a reason to exist, and this one has a job: History is a
/// different kind of action from Send and Receive, so its edge light is a
/// different colour, pace and direction from theirs. Purple is far enough from
/// both the brand blue and the header's light blue to read as deliberate rather
/// than as a shade of the same thing.
///
/// Two tones, one per brightness. The dark value over a near-white page would
/// wash out, so light takes it down a few stops rather than reusing it.
class HozaViolet {
  const HozaViolet._();

  /// Light lavender, for edges on the dark palette.
  static const Color midDark = Color(0xFFB79CFF);

  /// Deeper, so it still reads on a near-white surface.
  static const Color midLight = Color(0xFF7C5CD6);

  static Color mid(Brightness brightness) =>
      brightness == Brightness.dark ? midDark : midLight;
}
