import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../shared/widgets/hoza_logo.dart';
import '../../../shared/widgets/radar_pulse.dart';

/// Page one: the mark inside a live radar sweep.
class IntroMark extends StatelessWidget {
  const IntroMark({super.key, this.active = true});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return RadarPulse(
      size: 210,
      active: active,
      child: HozaLogo(size: 78),
    );
  }
}

/// Page two: two devices with something travelling between them.
///
/// Animated rather than a static diagram because the one thing this page has
/// to communicate is direction - which way the file goes, and that it goes
/// straight across rather than up to somewhere and back down.
class IntroTransfer extends StatefulWidget {
  const IntroTransfer({super.key, this.active = true});

  final bool active;

  @override
  State<IntroTransfer> createState() => _IntroTransferState();
}

class _IntroTransferState extends State<IntroTransfer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(IntroTransfer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    // Stopped when the page is off screen, so an unseen animation is not
    // burning frames behind the one the user is reading.
    widget.active ? _controller.repeat() : _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return SizedBox(
      height: 210,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // The path between the two devices.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 92),
            child: Container(height: 2, color: c.border),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) {
              final double t = Curves.easeInOutCubic.transform(
                _controller.value,
              );
              return Align(
                // Stays between the two device cards at any width, because the
                // alignment is fractional rather than a measured offset.
                alignment: Alignment(-0.52 + 1.04 * t, 0),
                child: Opacity(
                  // Fades in and out at the ends so it appears to leave one
                  // device and arrive at the other.
                  opacity: (1 - (t - 0.5).abs() * 2).clamp(0.25, 1.0),
                  child: child,
                ),
              );
            },
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                gradient: c.brandGradient,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const <Widget>[
              _DeviceChip(icon: Icons.smartphone_rounded, label: 'Phone'),
              _DeviceChip(
                icon: Icons.desktop_windows_rounded,
                label: 'Windows',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeviceChip extends StatelessWidget {
  const _DeviceChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            gradient: c.surfaceGradient,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: c.border),
            boxShadow: c.softShadow,
          ),
          child: Icon(icon, size: 32, color: c.primary),
        ),
        const SizedBox(height: Insets.md),
        Text(
          label,
          style: context.text.bodySmall?.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}

/// Page three: the three things that actually stop transfers working.
class IntroChecklist extends StatelessWidget {
  const IntroChecklist({super.key, required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return SizedBox(
      height: 210,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < items.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == items.length - 1 ? 0 : Insets.lg,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c.successSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: c.success,
                      ),
                    ),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: Text(
                        items[i],
                        style: context.text.bodyMedium
                            ?.copyWith(color: c.textPrimary),
                      ),
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

/// The page indicator. The active dot stretches into a bar rather than just
/// brightening, so position is readable at a glance.
class IntroDots extends StatelessWidget {
  const IntroDots({super.key, required this.count, required this.page});

  final int count;

  /// Fractional page position, so the indicator tracks the swipe itself
  /// instead of snapping when the page settles.
  final double page;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < count; i++)
          Builder(
            builder: (BuildContext context) {
              final double t = (1 - (page - i).abs()).clamp(0.0, 1.0);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 8 + 20 * t,
                height: 8,
                decoration: BoxDecoration(
                  color: Color.lerp(c.border, c.primary, t),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
              );
            },
          ),
      ],
    );
  }
}
