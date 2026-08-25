import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/hoza_device.dart';
import '../../../network/connection/connection_server.dart';
import '../../../shared/widgets/hoza_buttons.dart';
import '../../../shared/widgets/hoza_sheet.dart';
import '../../../shared/widgets/session_code_view.dart';
import '../connection_controller.dart';

/// Asks this user whether to let another device connect.
Future<void> showIncomingRequestSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // Answering has to be deliberate. Tapping away must not silently decline
    // or, worse, leave the other device waiting on nothing.
    isDismissible: false,
    enableDrag: false,
    builder: (BuildContext sheetContext) => const _IncomingRequestSheet(),
  );
}

class _IncomingRequestSheet extends StatefulWidget {
  const _IncomingRequestSheet();

  @override
  State<_IncomingRequestSheet> createState() => _IncomingRequestSheetState();
}

class _IncomingRequestSheetState extends State<_IncomingRequestSheet> {
  bool _closing = false;

  void _close([VoidCallback? action]) {
    if (_closing) return;
    _closing = true;
    action?.call();
    Navigator.of(context).pop();
  }

  IconData _icon(DevicePlatform platform) => switch (platform) {
        DevicePlatform.android || DevicePlatform.ios =>
          Icons.smartphone_rounded,
        DevicePlatform.windows => Icons.desktop_windows_rounded,
        DevicePlatform.macos || DevicePlatform.linux => Icons.laptop_rounded,
        DevicePlatform.unknown => Icons.devices_other_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final ConnectionController connection =
        context.watch<ConnectionController>();
    final IncomingRequest? request = connection.incoming;

    // Resolved without this user: it timed out, or the other device gave up.
    if (request == null) {
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
      return const SizedBox.shrink();
    }

    return HozaSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: SheetBadge(
              icon: _icon(request.device.platform),
              color: c.primary,
              background: c.primarySoft,
            ),
          ),
          const SizedBox(height: Insets.xl),
          Text(
            '${request.device.name} wants to connect',
            textAlign: TextAlign.center,
            style: context.text.headlineSmall,
          ),
          const SizedBox(height: Insets.sm),
          Text(
            '${request.device.platform.label} - ${request.device.address}',
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Insets.xl),
          SessionCodeView(code: request.code),
          const SizedBox(height: Insets.md),
          Text(
            'Only accept if this code matches the one on their screen.',
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(color: c.textTertiary),
          ),
          const SizedBox(height: Insets.xl),
          HozaPrimaryButton(
            label: 'Accept',
            icon: Icons.check_rounded,
            onPressed: () => _close(connection.acceptIncoming),
          ),
          const SizedBox(height: Insets.md),
          HozaSecondaryButton(
            label: 'Reject',
            onPressed: () => _close(connection.rejectIncoming),
          ),
        ],
      ),
    );
  }
}
