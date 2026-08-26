import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../shared/widgets/hoza_logo.dart';
import '../../../shared/widgets/radar_pulse.dart';
import '../../../shared/widgets/transfer_modes.dart';

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

/// Page two: every pairing HozaSend supports, each with something travelling
/// across it.
///
/// Three lanes rather than one, because the single phone-to-Windows diagram
/// that used to live here quietly answered a question nobody asked and left
/// the two that people do ask - "can it go phone to phone?" and "can it go
/// between two PCs?" - looking like a no.
///
/// Animated rather than static because direction is the point: the file goes
/// straight across, not up to somewhere and back down.
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
    const List<TransferMode> modes = TransferMode.all;

    return SizedBox(
      height: 210,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          for (int i = 0; i < modes.length; i++)
            _TransferLane(
              mode: modes[i],
              animation: _controller,
              // Offset so the three read as three separate journeys rather
              // than one bar of dots moving in formation.
              phase: i / modes.length,
            ),
        ],
      ),
    );
  }
}

/// One pairing: two devices, a track between them, and a file crossing it.
class _TransferLane extends StatelessWidget {
  const _TransferLane({
    required this.mode,
    required this.animation,
    required this.phase,
  });

  final TransferMode mode;
  final Animation<double> animation;

  /// Where in the loop this lane starts, 0 to 1.
  final double phase;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: 44,
          child: Row(
            children: <Widget>[
              _DeviceChip(icon: mode.from),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: Insets.sm),
                      child: _Track(),
                    ),
                    AnimatedBuilder(
                      animation: animation,
                      builder: (BuildContext context, Widget? child) {
                        final double t = Curves.easeInOutCubic.transform(
                          (animation.value + phase) % 1.0,
                        );
                        return Align(
                          // Fractional, so it stays between the two chips at
                          // any width without a measured offset.
                          alignment: Alignment(-1 + 2 * t, 0),
                          child: Opacity(
                            // Fades in and out at the ends, so it appears to
                            // leave one device and arrive at the other.
                            opacity: (1 - (t - 0.5).abs() * 2).clamp(0.25, 1.0),
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          gradient: c.brandGradient,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _DeviceChip(icon: mode.to),
            ],
          ),
        ),
        const SizedBox(height: Insets.xs),
        Text(
          mode.label,
          style: context.text.labelSmall?.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}

/// The hairline the file travels along.
class _Track extends StatelessWidget {
  const _Track();

  @override
  Widget build(BuildContext context) {
    return Container(height: 2, color: context.colors.border);
  }
}

class _DeviceChip extends StatelessWidget {
  const _DeviceChip({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: c.surfaceGradient,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
        boxShadow: c.softShadow,
      ),
      child: Icon(icon, size: 22, color: c.primary),
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
