import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/violet.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/hoza_device.dart';
import '../../core/services/network_settings_service.dart';
import '../../shared/widgets/fade_slide_in.dart';
import '../../shared/widgets/pill_button.dart';
import '../../shared/widgets/sheen_aura.dart';
import '../../shared/widgets/hoza_background.dart';
import '../../shared/widgets/glint_button.dart';
import '../../shared/widgets/hoza_buttons.dart';
import '../../shared/widgets/hoza_logo.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/shimmer_text.dart';
import '../../shared/widgets/status_pill.dart';
import '../../shared/widgets/transfer_modes.dart';
import '../connection/connection_controller.dart';
import '../connection/widgets/connect_sheet.dart';
import '../connection/widgets/incoming_request_sheet.dart';
import '../connection/widgets/manual_connect_sheet.dart';
import '../discovery/discovery_controller.dart';
import '../discovery/widgets/nearby_devices.dart';
import '../onboarding/widgets/folder_setup_sheet.dart';
import '../settings/settings_controller.dart';
import '../transfer/transfer_controller.dart';
import '../transfer/widgets/incoming_transfer_sheet.dart';

/// The home screen.
///
/// Identity, discovery and connecting are real from here. Choosing files and
/// moving them lands in Sections 5 and 6.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ConnectionController? _connection;
  TransferController? _transfer;

  /// Guards against stacking two incoming prompts if a second request lands
  /// while the first is still on screen.
  bool _promptVisible = false;
  bool _transferVisible = false;
  bool _offerVisible = false;
  bool _folderPromptShown = false;

  @override
  void initState() {
    super.initState();
    // Both start as soon as home exists, so this device is findable and
    // reachable without the user pressing anything. Deferred one frame because
    // each may notify listeners immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DiscoveryController>().start();
      context.read<ConnectionController>().start();
      _maybeAskAboutFolder();
    });
  }

  /// Asked once, the first time home is reached. Deliberately here rather than
  /// during onboarding, so someone who installed before this existed still
  /// gets told where their files go.
  Future<void> _maybeAskAboutFolder() async {
    if (_folderPromptShown) return;
    final SettingsController settings = context.read<SettingsController>();
    if (settings.hasPreparedFolder) return;
    _folderPromptShown = true;
    await showFolderSetupSheet(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ConnectionController connection = context
        .read<ConnectionController>();
    if (!identical(connection, _connection)) {
      _connection?.removeListener(_onConnectionChanged);
      _connection = connection..addListener(_onConnectionChanged);
    }

    final TransferController transfer = context.read<TransferController>();
    if (!identical(transfer, _transfer)) {
      _transfer?.removeListener(_onTransferChanged);
      _transfer = transfer..addListener(_onTransferChanged);
    }
  }

  @override
  void dispose() {
    _connection?.removeListener(_onConnectionChanged);
    _transfer?.removeListener(_onTransferChanged);
    super.dispose();
  }

  /// Incoming files arrive without this user pressing anything, so both the
  /// prompt and the progress screen have to come to them.
  void _onTransferChanged() {
    final TransferController? transfer = _transfer;
    if (transfer == null) return;

    if (transfer.incomingOffer != null && !_offerVisible) {
      _offerVisible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          _offerVisible = false;
          return;
        }
        await showIncomingTransferSheet(context);
        _offerVisible = false;
      });
      return;
    }

    if (_transferVisible) return;
    if (!transfer.isActive || transfer.isSending) return;
    _transferVisible = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _transferVisible = false;
        return;
      }
      await Navigator.of(context).pushNamed(AppRoutes.transfer);
      _transferVisible = false;
    });
  }

  void _onConnectionChanged() {
    final ConnectionController? connection = _connection;
    if (connection == null || _promptVisible || connection.incoming == null) {
      return;
    }
    _promptVisible = true;

    // Deferred because the notification can arrive mid-build, and pushing a
    // route during build throws.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _promptVisible = false;
        return;
      }
      await showIncomingRequestSheet(context);
      // Accepting leaves a live session. Show it, rather than dropping the
      // user back on a home screen that looks like nothing happened.
      if (mounted && connection.isConnected) await showSessionSheet(context);
      _promptVisible = false;
    });
  }

  /// Network status as the user should read it. "Connected" means connected to
  /// a local network; the internet is irrelevant here.
  (String, StatusTone, bool) _networkStatus(DiscoveryController discovery) {
    return switch (discovery.network) {
      NetworkState.checking => ('Checking network', StatusTone.working, true),
      // The one state where nothing can work at all. Said flatly and in red:
      // every other line on this screen is about finding devices, and none of
      // it means anything until this device is on a network.
      NetworkState.offline => ('Not connected', StatusTone.negative, false),
      NetworkState.ready =>
        discovery.isSearching
            ? ('Looking for devices', StatusTone.working, true)
            : ('Connected to local network', StatusTone.positive, false),
    };
  }

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = context.watch<SettingsController>();
    final DiscoveryController discovery = context.watch<DiscoveryController>();
    final ConnectionController connection = context
        .watch<ConnectionController>();
    final (String status, StatusTone tone, bool pulse) = _networkStatus(
      discovery,
    );

    return Scaffold(
      body: HozaBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              // Keeps the column readable on a wide monitor instead of
              // stretching a phone layout across 2000 logical pixels.
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  context.pagePadding,
                  Insets.lg,
                  context.pagePadding,
                  Insets.section,
                ),
                children: <Widget>[
                  // The header is lit as one block. The mark, the headline and
                  // the pills sit in the same slow blue light rather than the
                  // wordmark being the only lit thing on the page.
                  SheenAura(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        FadeSlideIn(
                          child: Row(
                            children: <Widget>[
                              const Expanded(child: HozaLockup()),
                              IconButton(
                                onPressed: () => Navigator.of(
                                  context,
                                ).pushNamed(AppRoutes.settings),
                                icon: const Icon(Icons.tune_rounded),
                                tooltip: 'Settings',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: Insets.section),

                        FadeSlideIn(
                          index: 1,
                          // Gold, and moving, for the same reason the wordmark
                          // is: this line and the name above it are the two
                          // things the page is actually saying.
                          child: ShimmerText(
                            AppConstants.tagline,
                            style: context.text.displayMedium,
                          ),
                        ),
                        const SizedBox(height: Insets.md),
                        FadeSlideIn(
                          index: 2,
                          child: Wrap(
                            spacing: Insets.sm,
                            runSpacing: Insets.sm,
                            children: <Widget>[
                              StatusPill(
                                label: status,
                                tone: tone,
                                pulse: pulse,
                              ),
                              StatusPill(
                                label: settings.deviceName.isEmpty
                                    ? 'This device'
                                    : settings.deviceName,
                              ),
                              // Without the listening port, other devices can
                              // find this one but never reach it. Worth saying
                              // plainly.
                              if (connection.serverError != null)
                                const StatusPill(
                                  label: 'Cannot receive',
                                  tone: StatusTone.negative,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Insets.section),

                  SectionHeader(
                    title: 'Nearby devices',
                    actionLabel: 'Search again',
                    onAction: discovery.retry,
                  ),
                  NearbyDevices(
                    onSelect: (HozaDevice device) =>
                        showConnectSheet(context, device),
                  ),
                  // Only once discovery has genuinely run out of things to
                  // try. Before that an empty list means "not yet", and this
                  // card would be answering a question nobody has asked.
                  if (discovery.seemsBlocked) ...<Widget>[
                    const SizedBox(height: Insets.lg),
                    const _BlockedHint(),
                  ],
                  const SizedBox(height: Insets.section),

                  _HomeActions(
                    onSend: () =>
                        Navigator.of(context).pushNamed(AppRoutes.selection),
                    onReceive: () =>
                        Navigator.of(context).pushNamed(AppRoutes.receive),
                    onHistory: () =>
                        Navigator.of(context).pushNamed(AppRoutes.history),
                  ),
                  // No recent-transfers list here. Past transfers live behind
                  // the History button above, which keeps home about the one
                  // thing it is for: finding a device and sending to it.
                  const SizedBox(height: Insets.section),
                  const _NetworkShortcuts(),
                  // Directly above the credit line, because it answers the
                  // question people ask before they press Send at all: does
                  // this work between my two phones, or only phone to PC? All
                  // three pairings work the same way, and none of them is a
                  // mode the user has to choose.
                  const FadeSlideIn(index: 3, child: TransferModes()),
                  const SizedBox(height: Insets.xl),
                  const _HomeFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens a system network screen, and says so if it could not.
///
/// The messenger is taken before the await, not the context after it: by the
/// time the platform answers, the widget that asked may be gone.
Future<void> _openSetting(BuildContext context, NetworkSetting setting) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  if (await NetworkSettingsService.open(setting)) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(content: Text("Couldn't open ${setting.label} settings.")),
    );
}

/// Shown when discovery has tried everything and found nobody.
///
/// The honest reading of that state is not "there are no devices here" - it is
/// "this network is not letting them see each other", and that has a small
/// number of causes, each with something the user can actually do. Naming the
/// likely one for this platform beats a generic apology: on Windows it is
/// nearly always the firewall prompt that got dismissed on first run, and on a
/// phone it is nearly always an access point that isolates its clients, which
/// no setting on the device can undo but a hotspot sidesteps entirely.
///
/// Connect by IP is offered on every platform, because it is the one route
/// that does not depend on unsolicited packets arriving.
class _BlockedHint extends StatelessWidget {
  const _BlockedHint();

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool hasFirewallScreen = NetworkSettingsService.supports(
      NetworkSetting.firewall,
    );

    final String explanation = switch (Platform.operatingSystem) {
      'windows' =>
        'Windows Firewall is the usual reason. If its prompt was dismissed '
            'the first time HozaSend ran, incoming connections stay blocked '
            'until you allow the app through.',
      'macos' =>
        'The macOS firewall is the usual reason. If it was set to block '
            'incoming connections, HozaSend cannot be reached until it is '
            'allowed through.',
      _ =>
        'This network may not let devices reach each other directly - common '
            'on hotel, campus and guest Wi-Fi. A phone hotspot always works.',
    };

    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: c.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.warning.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.shield_outlined, size: 18, color: c.warning),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(
                  'Still nothing found',
                  style: context.text.titleSmall?.copyWith(color: c.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          Text(
            explanation,
            style: context.text.bodySmall?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Insets.md),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: <Widget>[
              if (hasFirewallScreen)
                PillButton(
                  icon: Icons.security_rounded,
                  label: 'Firewall',
                  tone: c.warning,
                  tooltip: 'Open firewall settings',
                  onPressed: () =>
                      _openSetting(context, NetworkSetting.firewall),
                ),
              PillButton(
                icon: Icons.dns_rounded,
                label: 'Connect by IP',
                tooltip: 'Type the other device’s address',
                onPressed: () => showManualConnectSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shortcuts into the system screens this app leans on, and the way in that
/// needs no system screen at all.
///
/// HozaSend needs both devices on one network and can do nothing to put them
/// there: switching a radio on stopped being something an ordinary app may do
/// years ago, on every platform, and rightly so. What it can do is remove the
/// walk through Settings - which is the whole difference between "connect both
/// devices to the same Wi-Fi" as an instruction and as a button.
///
/// Connect by IP sits alongside them and is always present, on every platform.
/// It is the only route that does not depend on discovery working at all, so
/// it must not be reachable only from a card that appears when discovery has
/// already given up.
///
/// Small and on one line, always. Three full-height buttons at the foot of the
/// page would claim more attention than Send and Receive above them, and a
/// second row would make the last of the three look like an afterthought - so
/// they stay chips, and the row scales itself down rather than wrapping when a
/// narrow phone leaves less room than the three of them want.
///
/// Each carries its own colour on its badge, and its own pace and starting
/// point for the light crossing it, so the three read as three actions rather
/// than as one effect repeated: blue for Wi-Fi, cyan for Hotspot, and violet -
/// slowest, and last to be lit - for the fallback that is not part of the pair.
class _NetworkShortcuts extends StatelessWidget {
  const _NetworkShortcuts();

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool hasRadioScreens = NetworkSettingsService.supports(
      NetworkSetting.wifi,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.xl),
      // Scaled as one row rather than per button, so three pills that have to
      // shrink shrink together and keep the same text size as each other.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Nothing to offer on iOS or Linux, and a button that does nothing
            // is worse than no button.
            if (hasRadioScreens) ...<Widget>[
              GlintButton(
                icon: Icons.wifi_rounded,
                label: 'Wi-Fi',
                tooltip: 'Open Wi-Fi settings',
                onPressed: () => _openSetting(context, NetworkSetting.wifi),
              ),
              const SizedBox(width: Insets.sm),
              GlintButton(
                icon: Icons.wifi_tethering_rounded,
                label: 'Hotspot',
                // Cyan against the Wi-Fi chip's brand blue. The two are a pair
                // and should read as one row, but they are not the same
                // action, and two identical chips side by side make a user
                // read both labels to find out which is which.
                tone: c.accent,
                tooltip: 'Open hotspot settings',
                period: const Duration(milliseconds: 4400),
                phase: 0.34,
                onPressed: () => _openSetting(context, NetworkSetting.hotspot),
              ),
              const SizedBox(width: Insets.sm),
            ],
            GlintButton(
              icon: Icons.dns_rounded,
              label: 'Connect by IP',
              // Violet, and the slowest of the three. This is the fallback: it
              // should be as findable as the other two and still not read as
              // the first thing to try.
              tone: HozaViolet.mid(Theme.of(context).brightness),
              tooltip: 'Connect to a device by typing its address',
              period: const Duration(milliseconds: 6400),
              phase: 0.67,
              onPressed: () => showManualConnectSheet(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Version and credit, at the very bottom of the page.
///
/// Sits below everything and in the quietest colour the palette has: it should
/// be findable when someone goes looking, and invisible when they are not.
class _HomeFooter extends StatelessWidget {
  const _HomeFooter();

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final TextStyle? style = context.text.labelSmall?.copyWith(
      color: c.textTertiary,
    );

    return Column(
      children: <Widget>[
        Divider(color: c.border, height: 1),
        const SizedBox(height: Insets.lg),
        Text(
          '${AppConstants.appName} v${AppConstants.appVersion}',
          textAlign: TextAlign.center,
          style: style?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: Insets.xs),
        Text(AppConstants.copyright, textAlign: TextAlign.center, style: style),
      ],
    );
  }
}

/// Send and Receive. Side by side once there is room, stacked on a phone.
class _HomeActions extends StatelessWidget {
  const _HomeActions({
    required this.onSend,
    required this.onReceive,
    required this.onHistory,
  });

  final VoidCallback onSend;
  final VoidCallback onReceive;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    // Named actions rather than bare arrows. A diagonal arrow only says
    // "direction"; these say what the button does, and each one matches the
    // icon on the screen it opens - the send bar on the selection screen, and
    // the beacon at the centre of Receive.
    final Widget send = HozaPrimaryButton(
      label: 'Send Files',
      icon: Icons.send_rounded,
      onPressed: onSend,
    );
    final Widget receive = HozaSecondaryButton(
      label: 'Receive',
      icon: Icons.download_rounded,
      onPressed: onReceive,
    );

    // History sits on its own row in either layout, smaller than the two above
    // it and only as wide as its own words: it is where you go afterwards, not
    // one of the two things you came to do.
    //
    // Its edge light is gold and runs the other way round, slower. Three
    // buttons lit identically would say nothing about which is which; a
    // different light is what marks this one as a different kind of thing -
    // and purple is far enough from both the brand blue and the header's light
    // blue to read as deliberate rather than as a shade of the same thing.
    final Widget history = Center(
      child: HozaSecondaryButton(
        label: 'History',
        icon: Icons.history_rounded,
        onPressed: onHistory,
        expand: false,
        compact: true,
        edge: ButtonEdge(
          color: HozaViolet.mid(Theme.of(context).brightness),
          period: Motion.edge * 2,
          reverse: true,
        ),
      ),
    );

    if (context.isWide) {
      return Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: send),
              const SizedBox(width: Insets.lg),
              Expanded(child: receive),
            ],
          ),
          const SizedBox(height: Insets.md),
          history,
        ],
      );
    }
    return Column(
      children: <Widget>[
        send,
        const SizedBox(height: Insets.md),
        receive,
        const SizedBox(height: Insets.md),
        history,
      ],
    );
  }
}
