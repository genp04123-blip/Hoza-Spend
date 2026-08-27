import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import '../../shared/widgets/fade_slide_in.dart';
import '../../shared/widgets/hoza_app_bar.dart';
import '../../shared/widgets/hoza_background.dart';
import '../../shared/widgets/hoza_buttons.dart';
import '../../shared/widgets/hoza_card.dart';
import '../../shared/widgets/pulse_icon.dart';
import '../../shared/widgets/status_pill.dart';
import '../connection/connection_controller.dart';
import '../discovery/discovery_controller.dart';
import '../settings/settings_controller.dart';
import 'widgets/receive_beacon.dart';

/// The waiting room.
///
/// Receiving needs nothing from this user - the app is already listening the
/// moment it opens. This screen exists because "already working" is invisible,
/// and a person who just tapped Receive deserves to see that something is
/// happening, what name to look for on the other device, and what to do next.
class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = context.watch<SettingsController>();
    final DiscoveryController discovery = context.watch<DiscoveryController>();
    final ConnectionController connection =
        context.watch<ConnectionController>();

    final bool offline = discovery.network == NetworkState.offline;
    final List<PeerLink> connected = connection.connectedLinks;
    final int connectedCount = connected.length;
    final String deviceName =
        settings.deviceName.isEmpty ? 'This device' : settings.deviceName;

    return Scaffold(
      body: HozaBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: <Widget>[
                  const HozaAppBar(title: 'Receive'),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        context.pagePadding,
                        Insets.lg,
                        context.pagePadding,
                        Insets.section,
                      ),
                      children: <Widget>[
                        FadeSlideIn(
                          child: Center(
                            child: ReceiveBeacon(
                              size: 250,
                              // Stops sweeping when there is no network to be
                              // seen on, so the screen never animates a lie.
                              active: !offline,
                              child: PulseIcon(
                                // Swaps to a link the moment a device is on
                                // the other end, so the centre always shows
                                // the current state rather than a fixed label.
                                icon: connectedCount > 0
                                    ? Icons.link_rounded
                                    : Icons.download_rounded,
                                size: 88,
                                filled: true,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: Insets.section),

                        FadeSlideIn(
                          index: 1,
                          child: Text(
                            _title(
                              offline: offline,
                              connected: connectedCount > 0,
                            ),
                            textAlign: TextAlign.center,
                            style: context.text.headlineMedium,
                          ),
                        ),
                        const SizedBox(height: Insets.sm),
                        FadeSlideIn(
                          index: 2,
                          child: Text(
                            _subtitle(
                              offline: offline,
                              connectedCount: connectedCount,
                              // The name of the one device that is up, not
                              // whichever link the send screen happens to be
                              // pointed at - those are the same thing only
                              // until a second device joins.
                              peerName: connectedCount == 1
                                  ? connected.first.name
                                  : null,
                            ),
                            textAlign: TextAlign.center,
                            style: context.text.bodyLarge?.copyWith(
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: Insets.xl),

                        FadeSlideIn(
                          index: 3,
                          child: Center(
                            child: StatusPill(
                              label: offline
                                  ? 'No local network'
                                  : connectedCount > 1
                                      ? '$deviceName - $connectedCount '
                                          'devices connected'
                                      : 'Visible as $deviceName',
                              tone: offline
                                  ? StatusTone.warning
                                  : (connectedCount > 0
                                      ? StatusTone.positive
                                      : StatusTone.working),
                              pulse: !offline && connectedCount == 0,
                            ),
                          ),
                        ),
                        const SizedBox(height: Insets.section),

                        if (offline)
                          FadeSlideIn(
                            index: 4,
                            child: HozaPrimaryButton(
                              label: 'Try again',
                              icon: Icons.refresh_rounded,
                              onPressed: discovery.retry,
                            ),
                          )
                        else if (connectedCount == 0)
                          FadeSlideIn(
                            index: 4,
                            child: _Steps(deviceName: deviceName),
                          ),

                        const SizedBox(height: Insets.xl),
                        FadeSlideIn(
                          index: 5,
                          child: HozaSecondaryButton(
                            label: 'Done',
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                      ],
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

  static String _title({required bool offline, required bool connected}) {
    if (offline) return 'Not on a network';
    if (connected) return 'Connected';
    return 'Ready to receive';
  }

  /// Any of the connected devices can send, so with more than one the screen
  /// says how many rather than naming one of them and quietly implying the
  /// others went away.
  static String _subtitle({
    required bool offline,
    required int connectedCount,
    String? peerName,
  }) {
    if (offline) {
      return 'Join a Wi-Fi network or a phone hotspot. HozaSend does not need '
          'internet, only the same network as the other device.';
    }
    if (connectedCount > 1) {
      return 'Waiting for any of $connectedCount connected devices to send. '
          'You will be asked before anything is saved.';
    }
    if (connectedCount == 1) {
      return 'Waiting for ${peerName ?? 'the other device'} to send. You will '
          'be asked before anything is saved.';
    }
    return 'Leave this open. Nearby devices can now find this one and send to '
        'it.';
  }
}

/// What to do on the *other* device. The instructions belong here because this
/// is the screen the user is looking at while wondering why nothing has
/// happened yet.
class _Steps extends StatelessWidget {
  const _Steps({required this.deviceName});

  final String deviceName;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final List<String> steps = <String>[
      'Open HozaSend on the other device',
      'Pick "$deviceName" from its nearby list',
      'Accept the request when it appears here',
    ];

    return HozaCard(
      padding: const EdgeInsets.all(Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == steps.length - 1 ? 0 : Insets.lg,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: context.text.labelSmall?.copyWith(
                        color: c.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: context.text.bodyMedium
                          ?.copyWith(color: c.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
