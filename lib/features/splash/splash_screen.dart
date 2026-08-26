import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/share_intake_service.dart';
import '../../shared/widgets/shimmer_text.dart';
import '../settings/settings_controller.dart';

/// The palette the launch screen is pinned to.
///
/// A daylight sky, and the one screen in the app that does not follow the
/// user's theme. Two reasons it is fixed. The native window behind it is a
/// single colour that Android cannot vary per theme, so anything that moves
/// shows up as a flash on every open; and a launch screen is the one moment
/// where the product gets to say what it is, which it cannot do if it looks
/// like two different apps depending on a system setting.
///
/// Light blue because the whole product is about sending something into the
/// air. The mark is a winged envelope in orange - the one warm thing on a cool
/// page, which is exactly where the eye should land first.
class _Sky {
  const _Sky._();

  /// The colour of the native window, byte for byte the same as
  /// `android/app/src/main/res/drawable/launch_background.xml`. The Dart screen
  /// starts on this flat colour and blooms into the gradient below, so the
  /// handover from the OS splash has nothing to give away.
  static const Color flat = Color(0xFFE9F5FE);

  static const Color top = Color(0xFFF7FCFF);
  static const Color mid = Color(0xFFDCEFFC);
  static const Color deep = Color(0xFFBBDEF7);

  /// The light thrown behind the mark: white high up, a cool wash low down.
  static const Color highlight = Color(0xFFFFFFFF);
  static const Color wash = Color(0xFF7FC7EE);

  static const Color ink = Color(0xFF0C2C4C);
  static const Color inkSoft = Color(0xFF52789B);

  static const Color primary = Color(0xFF2158F0);
  static const Color accent = Color(0xFF0EA5C4);
}

/// The launch screen, shown on every open.
///
/// It also decides where the app opens: intro, device naming, or home.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// Long enough to read the name and watch the mark land, short enough not to
  /// be a toll booth on an app whose whole promise is speed.
  static const Duration _duration = Duration(milliseconds: 1800);

  /// The arrival. One controller staged with intervals: separate controllers
  /// would drift apart and make the choreography impossible to reason about.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  );

  /// The idle. Runs from the first frame and never stops, so nothing on screen
  /// is ever completely still - the sky drifts, the mark breathes, the light
  /// behind it swells. If a slow device holds the launch, the screen is alive
  /// rather than frozen on its last frame.
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  bool _started = false;

  /// The sky settling out of the flat native colour, and the light coming up
  /// behind the mark. First, because everything else needs somewhere to land.
  late final Animation<double> _bloom = _stage(0.00, 0.42, Curves.easeOutCubic);

  late final Animation<double> _icon = _stage(0.04, 0.34, Curves.easeOut);

  /// The flight itself, on an overshooting curve so the mark settles into
  /// place rather than sliding to a stop.
  late final Animation<double> _flight = _stage(0.04, 0.64, Motion.settle);

  /// Speed lines chasing it in. Alive only while it is moving.
  late final Animation<double> _trail = _stage(0.04, 0.64, Curves.linear);

  /// Thrown off as the mark lands, so the ring reads as caused by the arrival
  /// rather than as decoration that happens to be running.
  late final Animation<double> _ring = _stage(0.44, 1.00, Curves.easeOutCubic);

  late final Animation<double> _word = _stage(0.34, 0.72, Motion.standard);
  late final Animation<double> _tagline = _stage(0.48, 0.88, Motion.standard);
  late final Animation<double> _bar = _stage(0.24, 1.00, Curves.easeInOut);

  Animation<double> _stage(double begin, double end, Curve curve) {
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(begin, end, curve: curve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (context.reduceMotion) {
      // The setting is a real request. Show the finished frame and move on,
      // but still hold briefly so the app does not look like it skipped a
      // screen.
      _controller.value = 1;
      _idle.value = 0.5;
      Future<void>.delayed(const Duration(milliseconds: 420), _open);
      return;
    }
    _idle.repeat(reverse: true);
    _controller.forward().whenComplete(_open);
  }

  @override
  void dispose() {
    _controller.dispose();
    _idle.dispose();
    super.dispose();
  }

  /// Everything stored was already loaded before the first frame, so this is a
  /// decision, not a wait.
  void _open() {
    if (!mounted) return;
    final SettingsController settings = context.read<SettingsController>();
    _restoreStatusBar(settings);
    Navigator.of(context).pushReplacementNamed(
      switch ((settings.hasSeenIntro, settings.isOnboarded)) {
        (false, _) => AppRoutes.intro,
        (true, false) => AppRoutes.onboarding,
        (true, true) => AppRoutes.home,
      },
    );
    // Only now. A file shared into HozaSend opens the send screen on top of
    // whatever this just decided, and pushing it any earlier would put it
    // under the route replacing this one.
    ShareIntake.instance.ready();
  }

  /// This screen asks for dark status bar icons, because it is the only pale
  /// page in the app. Android keeps the last style it was handed, so giving it
  /// back on the way out is what stops the icons vanishing into the dark page
  /// underneath.
  void _restoreStatusBar(SettingsController settings) {
    final Brightness page = switch (settings.themeMode) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            page == Brightness.dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: page,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _Sky.flat,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _SkyBackdrop(bloom: _bloom, idle: _idle),

            // Centred composition rather than a column of spacers. Spacers made
            // the layout depend on the window height, which left a phone
            // cramped and a desktop window looking half empty.
            //
            // Held a little above true centre: the progress line sits at the
            // bottom, and a block centred against it reads as having sunk.
            Align(
              alignment: const Alignment(0, -0.14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _Mark(
                    icon: _icon,
                    flight: _flight,
                    trail: _trail,
                    ring: _ring,
                    bloom: _bloom,
                    idle: _idle,
                  ),
                  const SizedBox(height: Insets.lg),
                  _Rise(
                    animation: _word,
                    child: ShimmerText(
                      AppConstants.appName,
                      // Gold, the same gold as the home header, and forced to
                      // the light ramp: this page is pale whatever the system
                      // theme says, and the dark ramp over it would wash out.
                      brightness: Brightness.light,
                      period: const Duration(milliseconds: 2600),
                      style: context.text.displayMedium?.copyWith(
                        color: _Sky.ink,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: Insets.sm),
                  _TrackingText(
                    animation: _tagline,
                    text: 'SHARE WITHOUT THE INTERNET',
                    style: context.text.labelMedium?.copyWith(
                      color: _Sky.inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 64),
                child: _ProgressBar(bar: _bar, idle: _idle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sky: a vertical fall from near-white to a deeper blue, with two soft
/// lights drifting slowly across it.
///
/// It starts as the flat native colour and resolves into the gradient over the
/// first half second. That is the seam between the OS window and Flutter's
/// first frame, and blooming through it is what hides it.
///
/// Gradients, never a blur filter. This is the first thing a cold start has to
/// paint, on whatever phone the user owns.
class _SkyBackdrop extends StatelessWidget {
  const _SkyBackdrop({required this.bloom, required this.idle});

  final Animation<double> bloom;
  final Animation<double> idle;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[bloom, idle]),
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            painter: _SkyPainter(
              bloom: bloom.value.clamp(0.0, 1.0),
              drift: idle.value,
            ),
          );
        },
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  const _SkyPainter({required this.bloom, required this.drift});

  final double bloom;
  final double drift;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect rect = Offset.zero & size;

    Color from(Color colour) => Color.lerp(_Sky.flat, colour, bloom) ?? colour;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[from(_Sky.top), from(_Sky.mid), from(_Sky.deep)],
          stops: const <double>[0.0, 0.54, 1.0],
        ).createShader(rect),
    );

    // Two lights, opposite corners and opposite phases. Lighting a flat fill
    // from two directions is what keeps it a sky rather than a swatch.
    final double angle = drift * math.pi;

    _light(
      canvas: canvas,
      rect: rect,
      centre: Alignment(-0.55 + 0.10 * math.sin(angle), -0.70),
      radius: size.width * 0.95,
      colour: _Sky.highlight.withValues(
        alpha: bloom * (0.50 + 0.12 * math.cos(angle)),
      ),
    );
    _light(
      canvas: canvas,
      rect: rect,
      centre: Alignment(0.75, 0.80 - 0.10 * math.sin(angle)),
      radius: size.width * 0.80,
      colour: _Sky.wash.withValues(
        alpha: bloom * (0.20 + 0.08 * math.sin(angle)),
      ),
    );
  }

  void _light({
    required Canvas canvas,
    required Rect rect,
    required Alignment centre,
    required double radius,
    required Color colour,
  }) {
    final Offset origin = centre.withinRect(rect);
    final Rect circle = Rect.fromCircle(center: origin, radius: radius);
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..shader = RadialGradient(
          // A long fall to nothing: a straight ramp lands on a visible edge.
          colors: <Color>[
            colour,
            colour.withValues(alpha: colour.a * 0.40),
            colour.withValues(alpha: 0),
          ],
          stops: const <double>[0.0, 0.45, 1.0],
        ).createShader(circle),
    );
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) =>
      oldDelegate.bloom != bloom || oldDelegate.drift != drift;
}

/// The mark arriving, and everything its arrival throws off.
///
/// It flies in from the lower left along its own diagonal, banking level as it
/// lands and settling a hair past its resting place, with speed lines chasing
/// it and rings going out where it stops. The artwork is drawn mid-flight -
/// pointing up and to the right, speed lines trailing down to the left - so
/// entering from anywhere else would fight the drawing.
///
/// Once landed it never quite stops: it breathes on the idle loop, a few
/// pixels, slowly.
class _Mark extends StatelessWidget {
  const _Mark({
    required this.icon,
    required this.flight,
    required this.trail,
    required this.ring,
    required this.bloom,
    required this.idle,
  });

  final Animation<double> icon;
  final Animation<double> flight;
  final Animation<double> trail;
  final Animation<double> ring;
  final Animation<double> bloom;
  final Animation<double> idle;

  static const double _size = 150;
  static const double _field = 236;

  /// How far out along its own diagonal it starts.
  static const double _travel = 66;

  /// The bank it comes in on, in radians, unwinding to level as it lands.
  /// Small enough to feel rather than see.
  static const double _bank = 0.16;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _field,
      height: _field,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          _Halo(bloom: bloom, idle: idle),
          _Rings(ring: ring),
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: trail,
              builder: (BuildContext context, Widget? child) => CustomPaint(
                size: const Size.square(_field),
                painter: _TrailPainter(
                  progress: trail.value,
                  travel: _travel,
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[icon, flight, idle]),
            builder: (BuildContext context, Widget? child) {
              // Not clamped: the settle curve is meant to pass 1 and come back,
              // which is what turns a slide into an arrival.
              final double remaining = 1 - flight.value;

              // The breath only owns the mark once the flight has handed it
              // over, so the two never pull in different directions.
              final double landed = math.min(1.0, flight.value);
              final double breath =
                  (0.5 - Curves.easeInOut.transform(idle.value)) * 7 * landed;

              return Opacity(
                opacity: icon.value.clamp(0.0, 1.0),
                child: Transform.translate(
                  // In from the lower left, out along the flight path.
                  offset: Offset(
                    -_travel * remaining,
                    _travel * remaining + breath,
                  ),
                  child: Transform.rotate(
                    angle: _bank * remaining,
                    child: child,
                  ),
                ),
              );
            },
            // No shadow behind it. The artwork is a transparent envelope, so a
            // rounded-rect shadow would render as a floating grey box around
            // nothing.
            child: const _SplashMark(size: _size),
          ),
        ],
      ),
    );
  }
}

/// The light the mark sits in.
///
/// The artwork is cyan and orange on a pale blue page; without something white
/// behind it the wings sink into the sky. It swells and settles on the idle
/// loop, which is what stops the composition reading as a still.
class _Halo extends StatelessWidget {
  const _Halo({required this.bloom, required this.idle});

  final Animation<double> bloom;
  final Animation<double> idle;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[bloom, idle]),
        builder: (BuildContext context, Widget? child) {
          final double t = bloom.value.clamp(0.0, 1.0);
          final double breath = Curves.easeInOut.transform(idle.value);
          return Transform.scale(
            scale: 0.82 + t * 0.18 + breath * 0.04,
            child: Opacity(opacity: t, child: child),
          );
        },
        child: Container(
          width: 300,
          height: 300,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: <Color>[
                Color(0xF2FFFFFF),
                Color(0x66E4F5FF),
                Color(0x00E4F5FF),
              ],
              stops: <double>[0.0, 0.52, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

/// Two rings going out from where the mark lands.
///
/// The second is a beat behind the first, which is what makes it read as one
/// impact spreading rather than as two circles animating.
class _Rings extends StatelessWidget {
  const _Rings({required this.ring});

  final Animation<double> ring;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: ring,
        builder: (BuildContext context, Widget? child) => CustomPaint(
          size: const Size.square(_Mark._field),
          painter: _RingPainter(ring.value.clamp(0.0, 1.0)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final Offset centre = size.center(Offset.zero);
    final double base = size.shortestSide / 2;

    for (int i = 0; i < 2; i++) {
      // The trailing ring does nothing until the leading one is on its way out.
      final double phase = (t - i * 0.22) / (1 - i * 0.22);
      if (phase <= 0) continue;

      final double fade = (1 - phase) * (1 - phase);
      canvas.drawCircle(
        centre,
        base * (0.58 + phase * 0.46),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4 - i * 0.4
          ..color = (i == 0 ? _Sky.primary : _Sky.accent)
              .withValues(alpha: fade * (i == 0 ? 0.34 : 0.24)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.t != t;
}

/// The speed lines chasing the mark in.
///
/// They live only while it is moving - brightest mid-flight, gone by the time
/// it lands - because a speed line under a stationary object is just a scratch
/// on the page.
class _TrailPainter extends CustomPainter {
  const _TrailPainter({required this.progress, required this.travel});

  final double progress;
  final double travel;

  /// The flight path, normalised: down and to the left, where it came from.
  static const Offset _back = Offset(-0.7071, 0.7071);

  @override
  void paint(Canvas canvas, Size size) {
    final double t = progress.clamp(0.0, 1.0);
    final double life = math.sin(t * math.pi);
    if (life <= 0.02) return;

    final Offset mark = size.center(Offset.zero) +
        Offset(-travel * (1 - t), travel * (1 - t));

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 4; i++) {
      final Offset start = mark + _back * (46.0 + i * 27.0);
      final Offset end = start + _back * (20.0 + i * 5.0);
      canvas.drawLine(
        start,
        end,
        paint
          ..strokeWidth = 3.4 - i * 0.6
          ..color = _Sky.accent.withValues(alpha: life * (0.34 - i * 0.07)),
      );
    }
  }

  @override
  bool shouldRepaint(_TrailPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// The mark shown while the app opens.
///
/// Its own asset rather than the launcher icon: that one has to survive a
/// circular mask and so sits square in its frame, while this one is drawn
/// mid-flight with its own speed lines - which is the whole reason the entrance
/// above comes in from the lower left. It is also the only warm thing on a cool
/// page, so it takes the eye without being told to.
class _SplashMark extends StatelessWidget {
  const _SplashMark({required this.size});

  static const String asset = 'assets/icon/hoza_splash.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      // Contain: the artwork reaches the edges of its frame, and cover would
      // crop whichever side the aspect ratio decided to sacrifice.
      fit: BoxFit.contain,
      // Decoded at display size: the source is 512px square.
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      filterQuality: FilterQuality.medium,
    );
  }
}

/// Fade plus a small rise.
class _Rise extends StatelessWidget {
  const _Rise({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  /// How far it travels on the way in. Short: the word is arriving, not
  /// sliding in from somewhere else.
  static const double _distance = 18;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? built) {
        final double t = animation.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, _distance * (1 - t)),
            child: built,
          ),
        );
      },
      child: child,
    );
  }
}

/// A line that arrives by drawing itself together.
///
/// The letters start further apart than they end and close to their resting
/// tracking as they fade up. On a line already set wide it reads as the words
/// settling into place, and it is the only motion on the page that is about
/// the language rather than the mark.
class _TrackingText extends StatelessWidget {
  const _TrackingText({
    required this.animation,
    required this.text,
    required this.style,
  });

  final Animation<double> animation;
  final String text;
  final TextStyle? style;

  /// Where the tracking starts and where it lands.
  static const double _from = 7.5;
  static const double _to = 2.4;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double t = animation.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: style?.copyWith(letterSpacing: _from + (_to - _from) * t),
          ),
        );
      },
    );
  }
}

/// A line that fills over the launch.
///
/// Tied to the same controller as everything else, so it is a real measure of
/// the wait rather than a spinner that would keep turning if something hung.
/// A soft highlight travels along whatever has filled, which is the one thing
/// on screen moving at a constant rate - the sign that the app is working, not
/// stuck.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.bar, required this.idle});

  final Animation<double> bar;
  final Animation<double> idle;

  static const double _width = 118;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[bar, idle]),
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            size: const Size(_width, 3),
            painter: _BarPainter(
              fill: bar.value.clamp(0.0, 1.0),
              sheen: idle.value,
            ),
          );
        },
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({required this.fill, required this.sheen});

  final double fill;
  final double sheen;

  @override
  void paint(Canvas canvas, Size size) {
    final Radius radius = Radius.circular(size.height);
    final Rect track = Offset.zero & size;

    // Barely there. At this size a strong track reads as an empty bar the app
    // failed to fill.
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()..color = _Sky.ink.withValues(alpha: 0.10),
    );

    if (fill <= 0) return;
    final Rect filled = Rect.fromLTWH(0, 0, size.width * fill, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(filled, radius),
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[_Sky.primary, _Sky.accent],
        ).createShader(filled),
    );

    // The highlight, riding the filled part.
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(filled, radius));
    final double x = filled.width * sheen;
    final Rect glow = Rect.fromCircle(
      center: Offset(x, size.height / 2),
      radius: size.height * 4,
    );
    canvas.drawCircle(
      glow.center,
      glow.width / 2,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: 0.75),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(glow),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.sheen != sheen;
}
