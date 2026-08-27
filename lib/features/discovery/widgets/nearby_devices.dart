import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/hoza_device.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/fade_slide_in.dart';
import '../../../shared/widgets/hoza_card.dart';
import '../../../shared/widgets/pulse_icon.dart';
import '../../../shared/widgets/radar_pulse.dart';
import '../../connection/connection_controller.dart';
import '../discovery_controller.dart';
import 'device_tile.dart';

/// The nearby-devices area of the home screen.
///
/// Four states, each designed rather than defaulted: no network, scanning,
/// scanned but empty, and a live list.
class NearbyDevices extends StatelessWidget {
  const NearbyDevices({
    super.key,
    required this.onSelect,
    this.markTarget = false,
  });

  final ValueChanged<HozaDevice> onSelect;

  /// Marks the one connected device the send screen is aimed at, rather than
  /// showing every live link identically. Only the send screen has a target,
  /// so only the send screen turns this on.
  final bool markTarget;

  @override
  Widget build(BuildContext context) {
    // The four states replace each other in place, so the swap is cross-faded
    // and the height is animated. Without this, finding a device makes the
    // whole page below it jump, which reads as a glitch rather than a result.
    return AnimatedSize(
      duration: context.motion(Motion.normal),
      curve: Motion.standard,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: context.motion(Motion.normal),
        switchInCurve: Motion.standard,
        switchOutCurve: Motion.exit,
        // Stacked rather than laid out, so the outgoing state does not push
        // the incoming one around while both are on screen.
        layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
          alignment: Alignment.topCenter,
          // Passthrough, so each state is laid out at the same width it would
          // have had on its own - a loose stack would let a card shrink to
          // its text.
          fit: StackFit.passthrough,
          children: <Widget>[
            ...previous,
            ?current,
          ],
        ),
        child: _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final DiscoveryController discovery = context.watch<DiscoveryController>();

    if (discovery.network == NetworkState.offline) {
      final String? failure = discovery.errorMessage;
      return EmptyState(
        key: const ValueKey<String>('offline'),
        icon: Icons.wifi_off_rounded,
        title: failure == null ? 'No local network' : 'Discovery cannot start',
        message: failure ??
            'Connect this device to Wi-Fi or a phone hotspot. HozaSend does '
                'not need internet, only the same network as the other device.',
        actionLabel: 'Try again',
        onAction: discovery.retry,
      );
    }

    // Discovery beacons say what a device is offering, not what it is doing
    // with this one. The live sessions are the connection's to know, so the
    // rows for the devices we are actually talking to are marked here - and
    // those are the only rows that get a way to hang up.
    final ConnectionController connection =
        context.watch<ConnectionController>();

    final List<HozaDevice> devices = <HozaDevice>[...discovery.devices];

    // A device we hold a session with belongs on this list whether or not its
    // beacons are arriving. Connect by IP never produces one, and a phone that
    // drops off multicast keeps its socket open long after it stops being
    // announced - and in both cases the row carrying Disconnect is the last
    // thing that should quietly disappear.
    for (final PeerLink link in connection.links) {
      if (!link.isBusy) continue;
      if (devices.any((HozaDevice d) => d.isSameAs(link.device))) continue;
      devices.add(link.device);
    }

    if (devices.isEmpty) {
      if (discovery.isSearching ||
          discovery.network == NetworkState.checking) {
        return const _ScanningCard(key: ValueKey<String>('scanning'));
      }
      return EmptyState(
        key: const ValueKey<String>('empty'),
        icon: Icons.wifi_tethering_rounded,
        title: 'No devices nearby',
        message: 'Connect your devices to the same Wi-Fi or hotspot and '
            'HozaSend will find them automatically.',
        actionLabel: 'Search again',
        onAction: discovery.retry,
      );
    }

    return Column(
      key: const ValueKey<String>('devices'),
      children: <Widget>[
        for (int i = 0; i < devices.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == devices.length - 1 ? 0 : Insets.md,
            ),
            child: FadeSlideIn(
              // Keyed by device so each row keeps its own entrance state as
              // others appear and disappear around it.
              key: ValueKey<String>(devices[i].id),
              index: i,
              child: _tile(devices[i], connection),
            ),
          ),
      ],
    );
  }

  Widget _tile(HozaDevice device, ConnectionController connection) {
    // Matched on address as well as id: a session this device accepted was
    // built from the socket, and its id need not be the one the beacon
    // advertised. Every address the device is known at counts, because a
    // phone on two networks answers discovery on one and the connection on
    // the other, and matching only the listed address would leave the live
    // link looking like an idle row.
    final PeerLink? link = connection.linkFor(device);

    if (link == null) {
      return DeviceTile(device: device, onTap: () => onSelect(device));
    }

    // On its way up. Said on the row rather than only inside the sheet, so
    // starting a second connection does not make the first one look idle.
    if (!link.isConnected) {
      return DeviceTile(
        device: device.copyWith(status: DeviceStatus.connecting),
        onTap: () => onSelect(device),
      );
    }

    final bool isTarget = markTarget && identical(connection.active, link);
    return DeviceTile(
      device: device.copyWith(status: DeviceStatus.connected),
      statusLabel: isTarget ? 'Sending to' : null,
      onTap: () => onSelect(device),
      // Per link, not "the" link: hanging up on one device has to leave the
      // others exactly where they were.
      onDisconnect: () => connection.disconnectLink(link),
    );
  }
}

class _ScanningCard extends StatelessWidget {
  const _ScanningCard({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return HozaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.xl,
        vertical: Insets.lg,
      ),
      child: Column(
        children: <Widget>[
          // The rings already say "searching". The icon says what is being
          // searched for, so the two halves read as one sentence rather than
          // repeating each other - and a radar glyph inside a radar animation
          // put concentric circles inside concentric circles, which fought.
          // Smaller than it was: the radar is reassurance, not the subject of
          // the screen, and at 150 it pushed the send buttons below the fold
          // on a short phone.
          const RadarPulse(
            size: 118,
            child: PulseIcon(icon: Icons.devices_rounded, size: 47),
          ),
          const SizedBox(height: Insets.md),
          Text(
            'Finding nearby devices...',
            style: context.text.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Insets.sm),
          Text(
            'Make sure HozaSend is open on the other device.',
            style: context.text.bodySmall?.copyWith(color: c.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
