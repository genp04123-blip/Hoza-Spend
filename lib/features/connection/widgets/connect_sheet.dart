import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/hoza_device.dart';
import '../../../shared/widgets/hoza_buttons.dart';
import '../../../shared/widgets/hoza_sheet.dart';
import '../../../shared/widgets/pulse_icon.dart';
import '../../../shared/widgets/radar_pulse.dart';
import '../../../shared/widgets/session_code_view.dart';
import '../connection_controller.dart';

/// Starts a connection to [device] and shows its progress.
///
/// [fromSelection] tells the sheet it was opened from the selection screen, so
/// on success it offers Continue instead of pushing that same screen again.
Future<void> showConnectSheet(
  BuildContext context,
  HozaDevice device, {
  bool fromSelection = false,
}) {
  unawaited(context.read<ConnectionController>().connectTo(device));
  return showSessionSheet(context, fromSelection: fromSelection);
}

/// Shows the session sheet for a connection that already exists, which is what
/// the receiving side sees after accepting.
Future<void> showSessionSheet(
  BuildContext context, {
  bool fromSelection = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // Dismissing by tapping away would leave a live session with no visible
    // way back to it, so closing is always an explicit button.
    isDismissible: false,
    enableDrag: false,
    builder: (BuildContext sheetContext) =>
        _ConnectSheet(fromSelection: fromSelection),
  );
}

class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet({required this.fromSelection});

  final bool fromSelection;

  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  bool _closing = false;

  void _close(VoidCallback action) {
    if (_closing) return;
    _closing = true;
    action();
    Navigator.of(context).pop();
  }

  /// Closes the sheet and opens the selection screen. The navigator is read
  /// before the pop, because this context is gone straight after it.
  void _chooseFiles() => _leaveFor(AppRoutes.selection);

  void _waitToReceive() => _leaveFor(AppRoutes.receive);

  /// Closes the sheet and opens another screen, leaving the session running.
  /// The navigator is read before the pop, because this context is gone
  /// straight after it.
  void _leaveFor(String route) {
    if (_closing) return;
    _closing = true;
    final NavigatorState navigator = Navigator.of(context);
    navigator.pop();
    navigator.pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final ConnectionController connection =
        context.watch<ConnectionController>();
    return HozaSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _body(context, connection),
      ),
    );
  }

  List<Widget> _body(BuildContext context, ConnectionController connection) {
    final AppColors c = context.colors;
    final String name = connection.peer?.name ?? 'the other device';

    switch (connection.state) {
      case SessionState.connecting:
        return <Widget>[
          const Center(
            child: RadarPulse(
              // Same reason as the scanning card: broadcast arcs inside the
              // pulse would be the rings again, one size smaller. A link says
              // the part the animation does not.
              size: 128,
              child: PulseIcon(icon: Icons.link_rounded, size: 52),
            ),
          ),
          const SizedBox(height: Insets.xl),
          _title(context, 'Connecting to $name'),
          _subtitle(context, 'Reaching the device over your local network.'),
          const SizedBox(height: Insets.xl),
          HozaSecondaryButton(
            label: 'Cancel',
            onPressed: () => _close(connection.disconnect),
          ),
        ];

      case SessionState.awaitingApproval:
        return <Widget>[
          const Center(
            child: RadarPulse(
              // Reaching the device is done; what is left is a person
              // deciding, so the centre stops implying network activity.
              size: 128,
              child: PulseIcon(icon: Icons.hourglass_top_rounded, size: 52),
            ),
          ),
          const SizedBox(height: Insets.xl),
          _title(context, 'Waiting for $name'),
          _subtitle(
            context,
            'Accept the request on the other device. Check the code below '
            'matches the one on their screen.',
          ),
          const SizedBox(height: Insets.xl),
          SessionCodeView(code: connection.code ?? ''),
          const SizedBox(height: Insets.xl),
          HozaSecondaryButton(
            label: 'Cancel',
            onPressed: () => _close(connection.disconnect),
          ),
        ];

      case SessionState.connected:
        return <Widget>[
          Center(
            child: SheetBadge(
              icon: Icons.check_rounded,
              color: c.success,
              background: c.successSoft,
              animate: true,
            ),
          ),
          const SizedBox(height: Insets.xl),
          _title(context, 'Connected to $name'),
          // Either side can start, so the sheet has to offer both directions.
          // The device that pressed Accept is usually the one waiting to
          // receive, and until now this screen only let it send.
          _subtitle(context, 'This session is trusted. Send files, or wait to '
              'receive them.'),
          const SizedBox(height: Insets.xl),
          SessionCodeView(code: connection.code ?? ''),
          const SizedBox(height: Insets.xl),
          if (widget.fromSelection)
            HozaPrimaryButton(
              label: 'Continue',
              icon: Icons.check_rounded,
              onPressed: () => _close(() {}),
            )
          else
            HozaPrimaryButton(
              label: 'Choose files',
              icon: Icons.send_rounded,
              onPressed: _chooseFiles,
            ),
          const SizedBox(height: Insets.md),
          HozaSecondaryButton(
            label: 'Receive',
            icon: Icons.download_rounded,
            // Leaves the session up: the receive screen is where the user
            // waits, and dropping the connection to get there would undo the
            // pairing they just did.
            onPressed: _waitToReceive,
          ),
          const SizedBox(height: Insets.md),
          HozaSecondaryButton(
            label: 'Done',
            onPressed: () => _close(connection.disconnect),
          ),
        ];

      case SessionState.rejected:
      case SessionState.failed:
        final HozaDevice? peer = connection.peer;
        final bool retryable =
            connection.state == SessionState.failed && peer != null;
        return <Widget>[
          Center(
            child: SheetBadge(
              icon: connection.state == SessionState.rejected
                  ? Icons.block_rounded
                  : Icons.wifi_off_rounded,
              color: c.danger,
              background: c.dangerSoft,
            ),
          ),
          const SizedBox(height: Insets.xl),
          _title(
            context,
            connection.state == SessionState.rejected
                ? 'Request declined'
                : "Couldn't connect",
          ),
          _subtitle(context, connection.error?.message ?? ''),
          const SizedBox(height: Insets.xl),
          if (retryable) ...<Widget>[
            HozaPrimaryButton(
              label: 'Try Again',
              icon: Icons.refresh_rounded,
              onPressed: () {
                connection.dismiss();
                unawaited(connection.connectTo(peer));
              },
            ),
            const SizedBox(height: Insets.md),
          ],
          HozaSecondaryButton(
            label: 'Close',
            onPressed: () => _close(connection.dismiss),
          ),
        ];

      case SessionState.idle:
        return <Widget>[
          Center(
            child: SheetBadge(
              icon: Icons.link_off_rounded,
              color: c.textSecondary,
              background: c.surfaceMuted,
            ),
          ),
          const SizedBox(height: Insets.xl),
          _title(context, 'Disconnected'),
          _subtitle(context, 'The session has ended.'),
          const SizedBox(height: Insets.xl),
          HozaSecondaryButton(
            label: 'Close',
            onPressed: () => _close(connection.dismiss),
          ),
        ];
    }
  }

  Widget _title(BuildContext context, String text) => Text(
        text,
        textAlign: TextAlign.center,
        style: context.text.headlineSmall,
      );

  Widget _subtitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: Insets.sm),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: context.text.bodyMedium
              ?.copyWith(color: context.colors.textSecondary),
        ),
      );
}
