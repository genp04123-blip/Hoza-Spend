import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/violet.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/hoza_device.dart';
import '../../shared/widgets/fade_slide_in.dart';
import '../../shared/widgets/sheen_aura.dart';
import '../../shared/widgets/hoza_background.dart';
import '../../shared/widgets/hoza_buttons.dart';
import '../../shared/widgets/hoza_logo.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/shimmer_text.dart';
import '../../shared/widgets/status_pill.dart';
import '../connection/connection_controller.dart';
import '../connection/widgets/connect_sheet.dart';
import '../connection/widgets/incoming_request_sheet.dart';
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
    final ConnectionController connection =
        context.read<ConnectionController>();
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
      NetworkState.ready => discovery.isSearching
          ? ('Looking for devices', StatusTone.working, true)
          : ('Connected to local network', StatusTone.positive, false),
    };
  }

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = context.watch<SettingsController>();
    final DiscoveryController discovery = context.watch<DiscoveryController>();
    final ConnectionController connection =
        context.watch<ConnectionController>();
    final (String status, StatusTone tone, bool pulse) =
        _networkStatus(discovery);

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
                                onPressed: () => Navigator.of(context)
                                    .pushNamed(AppRoutes.settings),
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
                  const SizedBox(height: Insets.section),

                  _HomeActions(
                    onSend: () => Navigator.of(context)
                        .pushNamed(AppRoutes.selection),
                    onReceive: () =>
                        Navigator.of(context).pushNamed(AppRoutes.receive),
                    onHistory: () =>
                        Navigator.of(context).pushNamed(AppRoutes.history),
                  ),
                  // No recent-transfers list here. Past transfers live behind
                  // the History button above, which keeps home about the one
                  // thing it is for: finding a device and sending to it.
                  const SizedBox(height: Insets.section),
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

/// Version and credit, at the very bottom of the page.
///
/// Sits below everything and in the quietest colour the palette has: it should
/// be findable when someone goes looking, and invisible when they are not.
class _HomeFooter extends StatelessWidget {
  const _HomeFooter();

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final TextStyle? style =
        context.text.labelSmall?.copyWith(color: c.textTertiary);

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
        Text(
          AppConstants.copyright,
          textAlign: TextAlign.center,
          style: style,
        ),
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
