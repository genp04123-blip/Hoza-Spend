import 'package:flutter/animation.dart';

/// Spacing scale, 4pt base. Use these instead of ad-hoc numbers so every screen
/// shares one rhythm.
class Insets {
  const Insets._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double section = 32;

  /// Horizontal page padding on phones.
  static const double page = 20;

  /// Horizontal page padding once the window is wide enough for desktop.
  static const double pageDesktop = 40;
}

/// Corner-radius scale. Large, soft corners are part of the brand.
class Radii {
  const Radii._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
  static const double pill = 999;
}

/// Motion tokens. Durations are never invented at the call site; pick one of
/// these so the whole app accelerates and settles the same way.
class Motion {
  const Motion._();

  /// Hovers, taps, colour changes.
  static const Duration fast = Duration(milliseconds: 160);

  /// The default: entrances, list items, expand and collapse.
  static const Duration normal = Duration(milliseconds: 260);

  /// Page transitions and larger surfaces.
  static const Duration slow = Duration(milliseconds: 420);

  /// Looping ambient motion: radar sweep, connection pulse.
  static const Duration ambient = Duration(milliseconds: 2600);

  /// A press going down. Shorter than anything else in the app: the finger is
  /// already there, so any delay reads as lag rather than as motion.
  static const Duration press = Duration(milliseconds: 90);

  /// The release. Longer than the press, so the surface settles back instead
  /// of snapping - that asymmetry is most of what makes a button feel physical.
  static const Duration release = Duration(milliseconds: 240);

  /// One lap of an edge light. Slow enough to read as lighting rather than as
  /// an animation asking for attention.
  static const Duration edge = Duration(milliseconds: 4600);

  /// Delay between staggered siblings such as file cards or device rows.
  static const Duration stagger = Duration(milliseconds: 55);

  /// Decelerating standard curve, used for most entrances.
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);

  /// For things leaving the screen.
  static const Curve exit = Curves.easeInCubic;

  /// Gentle overshoot. Reserved for success moments so it stays special.
  static const Curve emphasized = Cubic(0.16, 1.0, 0.3, 1.0);

  /// Coming back up from a press: a hair past the resting size, then settle.
  /// The overshoot is small enough to feel rather than see.
  static const Curve settle = Cubic(0.34, 1.28, 0.64, 1.0);
}

/// Layout breakpoints. Windows gets a real desktop layout, not a stretched
/// phone one.
class Breakpoints {
  const Breakpoints._();

  static const double compact = 600;
  static const double medium = 900;
  static const double expanded = 1200;
}
