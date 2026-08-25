import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import '../../shared/widgets/hoza_buttons.dart';
import '../settings/settings_controller.dart';
import 'widgets/intro_backdrop.dart';
import 'widgets/intro_illustrations.dart';

/// What one intro page says.
class _IntroPage {
  const _IntroPage({
    required this.title,
    required this.body,
    required this.build,
  });

  final String title;
  final String body;

  /// Takes whether this page is the one on screen, so an off-screen animation
  /// can stop rather than run unseen.
  final Widget Function(bool active) build;
}

/// The first-launch walkthrough: what HozaSend is, how to use it, and the
/// three things that actually stop it working.
///
/// Three pages, not five. Everything here is something a user cannot discover
/// on their own - especially the firewall prompt, which is the single most
/// common reason two devices never see each other.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final PageController _controller = PageController();

  /// Fractional, so the indicator and the parallax follow the finger rather
  /// than snapping when the page settles.
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final double? page = _controller.page;
      if (page == null || page == _page) return;
      setState(() => _page = page);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  late final List<_IntroPage> _pages = <_IntroPage>[
    _IntroPage(
      title: 'Share without the internet',
      body: 'HozaSend moves files straight between your devices over Wi-Fi or '
          'a phone hotspot. Nothing is uploaded, there is no account, and it '
          'keeps working with no internet at all.',
      build: (bool active) => IntroMark(active: active),
    ),
    _IntroPage(
      title: 'Open, pick, send',
      body: 'Open HozaSend on both devices and they find each other '
          'automatically. Tap the one you want, choose your files, and send.',
      build: (bool active) => IntroTransfer(active: active),
    ),
    _IntroPage(
      title: 'Three things to know',
      body: Platform.isWindows
          ? 'The first time you run HozaSend, Windows asks about the firewall. '
              'Allow it, or other devices will never find this one.'
          : 'Keep HozaSend open on the other device while you transfer.',
      build: (bool active) => IntroChecklist(
        items: <String>[
          'Both devices on the same Wi-Fi or hotspot',
          if (Platform.isWindows)
            'Allow HozaSend through the Windows firewall'
          else
            'Keep the screen on while transferring',
          'Keep HozaSend open on both devices',
        ],
      ),
    ),
  ];

  bool get _isLast => _page.round() >= _pages.length - 1;

  Future<void> _finish() async {
    final SettingsController settings = context.read<SettingsController>();
    await settings.markIntroSeen();
    if (!mounted) return;

    final NavigatorState navigator = Navigator.of(context);
    // Replayed from Settings, so just go back where they came from.
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushReplacementNamed(
      settings.isOnboarded ? AppRoutes.home : AppRoutes.onboarding,
    );
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(duration: Motion.slow, curve: Motion.standard);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Scaffold(
      body: IntroBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: <Widget>[
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.pagePadding - Insets.sm,
                        vertical: Insets.sm,
                      ),
                      child: AnimatedOpacity(
                        // Nothing to skip on the last page; the primary button
                        // already says the same thing.
                        opacity: _isLast ? 0 : 1,
                        duration: Motion.fast,
                        child: TextButton(
                          onPressed: _isLast ? null : _finish,
                          style: TextButton.styleFrom(
                            foregroundColor: c.textSecondary,
                          ),
                          child: const Text('Skip'),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _pages.length,
                      itemBuilder: (BuildContext context, int index) {
                        return _IntroPageView(
                          page: _pages[index],
                          // How far this page is from the viewport centre.
                          // Drives the parallax and the fade.
                          delta: index - _page,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: Insets.xl),
                  IntroDots(count: _pages.length, page: _page),
                  const SizedBox(height: Insets.xl),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      context.pagePadding,
                      0,
                      context.pagePadding,
                      Insets.xxl,
                    ),
                    child: HozaPrimaryButton(
                      label: _isLast ? 'Get started' : 'Next',
                      icon: _isLast
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded,
                      onPressed: _next,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One page, with the illustration travelling further than the text.
///
/// The offset difference is what gives the swipe depth: the artwork reads as
/// sitting behind the words rather than on the same sheet of paper.
class _IntroPageView extends StatelessWidget {
  const _IntroPageView({required this.page, required this.delta});

  final _IntroPage page;
  final double delta;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final double distance = delta.abs().clamp(0.0, 1.0);
    final double fade = 1 - distance;

    return Opacity(
      opacity: fade,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.pagePadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Transform.translate(
              offset: Offset(delta * 70, 0),
              child: page.build(distance < 0.5),
            ),
            const SizedBox(height: Insets.section),
            Transform.translate(
              offset: Offset(delta * 28, 0),
              child: Column(
                children: <Widget>[
                  Text(
                    page.title,
                    textAlign: TextAlign.center,
                    style: context.text.headlineMedium,
                  ),
                  const SizedBox(height: Insets.md),
                  Text(
                    page.body,
                    textAlign: TextAlign.center,
                    style: context.text.bodyLarge
                        ?.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
