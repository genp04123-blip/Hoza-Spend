import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/hoza_device.dart';
import '../../../network/discovery/network_info.dart';
import '../../../shared/widgets/hoza_buttons.dart';
import '../../../shared/widgets/hoza_sheet.dart';
import '../../../shared/widgets/hoza_text_field.dart';
import '../../../shared/widgets/pill_button.dart';
import 'connect_sheet.dart';

/// Asks for an address and connects straight to it, skipping discovery.
///
/// The escape hatch for every network where the automatic path cannot work.
/// Discovery leans on packets reaching a device that never asked for them -
/// broadcast, or an unsolicited unicast greeting - and a fair number of
/// networks will not carry those: a firewall dropping inbound UDP on one side,
/// an access point set to isolate its clients, two devices on subnets that
/// route to each other but share no broadcast domain, a VPN capturing the
/// route. On all of those a connection the user *initiates* still goes
/// through, because it is an ordinary outbound TCP connection and every
/// network in the world carries those.
///
/// Not a workaround for all of them: an access point enforcing client
/// isolation drops device-to-device traffic whoever started it, and nothing in
/// an app can undo that. Which is why this screen also shows the addresses
/// this device is reachable at - so the two users can try it from the other
/// end, and find out in ten seconds rather than by guessing.
Future<void> showManualConnectSheet(BuildContext context) async {
  final HozaDevice? target = await showModalBottomSheet<HozaDevice>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => const _ManualConnectSheet(),
  );
  if (target == null || !context.mounted) return;
  await showConnectSheet(context, target);
}

class _ManualConnectSheet extends StatefulWidget {
  const _ManualConnectSheet();

  @override
  State<_ManualConnectSheet> createState() => _ManualConnectSheetState();
}

class _ManualConnectSheetState extends State<_ManualConnectSheet> {
  final TextEditingController _controller = TextEditingController();

  late final Future<List<LocalAddress>> _own = NetworkInfo.localAddresses();

  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Splits what was typed into an address and a port.
  ///
  /// The port is accepted but almost never needed - both ends use the same
  /// one - so it is an optional suffix on the single field rather than a
  /// second box that would be empty every time. Returns null for anything that
  /// is not a usable IPv4 address, which is what the message below the field
  /// is for.
  (String, int)? _parse(String raw) {
    String host = raw.trim();
    if (host.isEmpty) return null;

    int port = AppConstants.transferPort;
    final int colon = host.lastIndexOf(':');
    if (colon > 0) {
      final int? typed = int.tryParse(host.substring(colon + 1));
      if (typed == null || typed < 1 || typed > 65535) return null;
      port = typed;
      host = host.substring(0, colon);
    }

    if (Ipv4.parse(host) == null) return null;
    return (host, port);
  }

  void _submit() {
    final (String, int)? parsed = _parse(_controller.text);
    if (parsed == null) {
      setState(() {
        _error = 'That is not an address. It looks like 192.168.1.5.';
      });
      return;
    }

    final (String address, int port) = parsed;
    // A placeholder identity. The real name, platform and id all arrive in the
    // welcome message a moment after the socket opens, and the connection
    // layer swaps them in - so the sheet behind this one starts out saying the
    // address and finishes saying the device's name.
    Navigator.of(context).pop(
      HozaDevice(
        id: 'manual:$address:$port',
        name: address,
        platform: DevicePlatform.unknown,
        address: address,
        port: port,
        appVersion: '',
        lastSeen: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return HozaSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: SheetBadge(
              icon: Icons.dns_rounded,
              color: c.primary,
              background: c.primarySoft,
            ),
          ),
          const SizedBox(height: Insets.xl),
          Text(
            'Connect by IP',
            textAlign: TextAlign.center,
            style: context.text.headlineSmall,
          ),
          Padding(
            padding: const EdgeInsets.only(top: Insets.sm),
            child: Text(
              'For networks where devices cannot find each other on their own. '
              'Type the address shown on the other device.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(
                color: c.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: Insets.xl),

          _OwnAddresses(addresses: _own),
          const SizedBox(height: Insets.lg),

          HozaTextField(
            controller: _controller,
            autofocus: true,
            hintText: '192.168.1.5',
            prefixIcon: Icons.language_rounded,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submit(),
            // Clears the complaint as soon as the user starts fixing it,
            // rather than leaving it up while they type the correction.
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          if (_error case final String message)
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm),
              child: Text(
                message,
                style: context.text.bodySmall?.copyWith(color: c.danger),
              ),
            ),
          const SizedBox(height: Insets.xl),

          HozaPrimaryButton(
            label: 'Connect',
            icon: Icons.link_rounded,
            onPressed: _submit,
          ),
          const SizedBox(height: Insets.md),
          HozaSecondaryButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// The addresses this device can be reached at, for the other user to type.
///
/// Half of the point of the screen. If the connection cannot be made in this
/// direction it may well work in the other, and a user who can only read their
/// own address off a Settings screen four taps away will not try.
class _OwnAddresses extends StatelessWidget {
  const _OwnAddresses({required this.addresses});

  final Future<List<LocalAddress>> addresses;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return FutureBuilder<List<LocalAddress>>(
      future: addresses,
      builder: (
        BuildContext context,
        AsyncSnapshot<List<LocalAddress>> snapshot,
      ) {
        final List<LocalAddress> found = snapshot.data ?? const <LocalAddress>[];
        if (found.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(Insets.lg),
          decoration: BoxDecoration(
            color: c.surfaceMuted,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                found.length == 1
                    ? 'This device is at'
                    : 'This device is at one of',
                style: context.text.labelSmall?.copyWith(
                  color: c.textTertiary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: Insets.sm),
              for (final LocalAddress local in found)
                Padding(
                  padding: const EdgeInsets.only(top: Insets.xs),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          local.address,
                          style: context.text.bodyLarge?.copyWith(
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                      _CopyButton(value: local.address),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.value});

  final String value;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    // Confirmed on the button itself rather than in a snack bar, which would
    // cover the field the user is about to type in.
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return PillButton(
      icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
      tone: _copied ? context.colors.success : null,
      tooltip: 'Copy address',
      onPressed: _copy,
    );
  }
}
