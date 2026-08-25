import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/hoza_device.dart';
import '../../../shared/widgets/edge_light.dart';
import '../../../shared/widgets/hoza_card.dart';
import '../../../shared/widgets/status_pill.dart';

/// One discovered device in the nearby list.
class DeviceTile extends StatelessWidget {
  const DeviceTile({super.key, required this.device, this.onTap});

  final HozaDevice device;
  final VoidCallback? onTap;

  IconData get _icon => switch (device.platform) {
        DevicePlatform.android || DevicePlatform.ios =>
          Icons.smartphone_rounded,
        DevicePlatform.windows => Icons.desktop_windows_rounded,
        DevicePlatform.macos || DevicePlatform.linux => Icons.laptop_rounded,
        DevicePlatform.unknown => Icons.devices_other_rounded,
      };

  (String, StatusTone) get _status => switch (device.status) {
        DeviceStatus.available => ('Available', StatusTone.neutral),
        DeviceStatus.connecting => ('Connecting', StatusTone.working),
        DeviceStatus.connected => ('Connected', StatusTone.positive),
        DeviceStatus.busy => ('Busy', StatusTone.warning),
        DeviceStatus.unavailable => ('Unavailable', StatusTone.negative),
      };

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final (String label, StatusTone tone) = _status;

    final Widget card = HozaCard(
      onTap: onTap,
      // A slim row: the device name and its status are the whole content, and
      // a taller card only pushes the next device off the screen.
      radius: Radii.md,
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.sm,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.primarySoft,
              borderRadius: BorderRadius.circular(Radii.xs),
            ),
            child: Icon(_icon, size: 19, color: c.primary),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  device.name,
                  style: context.text.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  // The address is genuinely useful here: it is how a user
                  // tells two identically named phones apart.
                  '${device.platform.label} - ${device.address}',
                  style:
                      context.text.bodySmall?.copyWith(color: c.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.md),
          StatusPill(
            label: label,
            tone: tone,
            pulse: device.status == DeviceStatus.connecting,
          ),
        ],
      ),
    );

    if (device.status != DeviceStatus.connected) return card;

    // A live link, said with the same edge language the primary button uses
    // for a live action - in success green, because that is what "connected"
    // is coloured everywhere else in the app.
    return EdgeLight(
      radius: Radii.md,
      color: c.success,
      intensity: 0.75,
      duration: Motion.edge * 1.2,
      child: card,
    );
  }
}
