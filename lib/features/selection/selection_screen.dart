import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/models/hoza_device.dart';
import '../../core/models/transfer.dart';
import '../../core/services/file_picker_service.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/fade_slide_in.dart';
import '../../shared/widgets/file_drop_target.dart';
import '../../shared/widgets/hoza_app_bar.dart';
import '../../shared/widgets/hoza_background.dart';
import '../../shared/widgets/hoza_buttons.dart';
import '../../shared/widgets/section_header.dart';
import '../connection/connection_controller.dart';
import '../connection/widgets/connect_sheet.dart';
import '../discovery/widgets/device_tile.dart';
import '../discovery/widgets/nearby_devices.dart';
import '../transfer/transfer_controller.dart';
import 'selection_controller.dart';
import 'widgets/choose_files_card.dart';
import 'widgets/file_card.dart';

/// Pick what to send, and who to send it to, on one screen.
///
/// Both entry points land here: "Send Files" from home, and "Choose files" from
/// a session that is already connected. Whichever is missing - the files or the
/// device - is what the screen asks for.
class SelectionScreen extends StatelessWidget {
  const SelectionScreen({super.key});

  /// Starts the transfer and moves straight to the progress screen. The send
  /// itself is not awaited here - the transfer screen watches the controller.
  void _send(BuildContext context, SelectionController selection) {
    unawaited(context.read<TransferController>().send(selection.files));
    Navigator.of(context).pushNamed(AppRoutes.transfer);
  }

  @override
  Widget build(BuildContext context) {
    final SelectionController selection = context.watch<SelectionController>();
    final ConnectionController connection = context
        .watch<ConnectionController>();

    return Scaffold(
      body: FileDropTarget(
        onDropped: (List<String> paths) => unawaited(selection.addPaths(paths)),
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            // The desktop convention for "open a file", and the one thing a
            // keyboard user does most on this screen. Both modifiers are bound
            // rather than branching on the platform: Cmd is meaningless on
            // Windows and Ctrl is unused here on a Mac, so neither can collide.
            const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
                unawaited(selection.addFiles()),
            const SingleActivator(LogicalKeyboardKey.keyO, meta: true): () =>
                unawaited(selection.addFiles()),
          },
          child: Focus(
            autofocus: true,
            child: HozaBackground(
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      children: <Widget>[
                        HozaAppBar(
                          title: 'Send files',
                          actions: <Widget>[
                            if (selection.isNotEmpty)
                              TextButton(
                                onPressed: selection.clear,
                                style: TextButton.styleFrom(
                                  foregroundColor: context.colors.textSecondary,
                                ),
                                child: const Text('Clear'),
                              ),
                          ],
                        ),
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.fromLTRB(
                              context.pagePadding,
                              Insets.sm,
                              context.pagePadding,
                              Insets.xxl,
                            ),
                            children: <Widget>[
                              _FilesSection(selection: selection),
                              const SizedBox(height: Insets.section),
                              _TargetSection(connection: connection),
                            ],
                          ),
                        ),
                        // The bar rises into place the moment the first file
                        // lands in the queue, so the send action announces
                        // itself instead of blinking into existence under the
                        // user's thumb.
                        AnimatedSize(
                          duration: context.motion(Motion.normal),
                          curve: Motion.standard,
                          alignment: Alignment.topCenter,
                          child: selection.isEmpty
                              ? const SizedBox(width: double.infinity)
                              : FadeSlideIn(
                                  offset: 20,
                                  child: _SendBar(
                                    selection: selection,
                                    connection: connection,
                                    onSend: () => _send(context, selection),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilesSection extends StatelessWidget {
  const _FilesSection({required this.selection});

  final SelectionController selection;

  @override
  Widget build(BuildContext context) {
    if (selection.isEmpty) {
      // The whole card is the target, rather than an empty state with a small
      // link in it - picking files is the only thing this screen is for.
      return ChooseFilesCard(
        busy: selection.isPicking,
        canDrop: FileDropTarget.isSupported,
        onChoose: selection.isPicking ? null : selection.addFiles,
      );
    }

    final List<TransferFile> files = selection.files;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title:
              '${files.length} '
              '${files.length == 1 ? 'file' : 'files'} - '
              '${Formatters.bytes(selection.totalBytes)}',
          actionLabel: selection.isPicking ? 'Opening...' : 'Add files',
          onAction: selection.isPicking ? null : selection.addFiles,
        ),
        for (int i = 0; i < files.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == files.length - 1 ? 0 : Insets.md,
            ),
            child: FadeSlideIn(
              // Keyed so a removal does not make every card below it replay
              // its entrance.
              key: ValueKey<String>(files[i].id),
              index: i,
              child: FileCard(
                file: files[i],
                onRemove: () => selection.remove(files[i].id),
              ),
            ),
          ),
        if (FilePickerService.supportsFolders) ...<Widget>[
          const SizedBox(height: Insets.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: selection.isPicking ? null : selection.addFolder,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('Add a folder'),
              style: TextButton.styleFrom(
                foregroundColor: context.colors.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Who the files are going to. A connected device is shown as a single card;
/// otherwise the nearby list appears here so the user can pick without
/// leaving the screen.
class _TargetSection extends StatelessWidget {
  const _TargetSection({required this.connection});

  final ConnectionController connection;

  @override
  Widget build(BuildContext context) {
    final HozaDevice? peer = connection.peer;

    if (connection.isConnected && peer != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(title: 'Sending to'),
          DeviceTile(
            device: peer.copyWith(status: DeviceStatus.connected),
            onTap: () => showSessionSheet(context, fromSelection: true),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SectionHeader(title: 'Send to'),
        NearbyDevices(
          onSelect: (HozaDevice device) =>
              showConnectSheet(context, device, fromSelection: true),
        ),
      ],
    );
  }
}

/// The action bar pinned below the list, so the send button stays reachable
/// however many files are queued.
class _SendBar extends StatelessWidget {
  const _SendBar({
    required this.selection,
    required this.connection,
    required this.onSend,
  });

  final SelectionController selection;
  final ConnectionController connection;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final HozaDevice? peer = connection.peer;
    final bool ready = connection.isConnected && peer != null;

    return Container(
      padding: EdgeInsets.fromLTRB(
        context.pagePadding,
        Insets.lg,
        context.pagePadding,
        Insets.lg,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!ready)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.md),
              child: Text(
                'Choose a device above to send to.',
                style: context.text.bodySmall?.copyWith(color: c.textSecondary),
              ),
            ),
          HozaPrimaryButton(
            label: ready
                ? 'Send to ${peer.name}'
                : '${selection.count} ready to send',
            // The same icon the home screen's Send button carries, so the
            // action keeps one face from the tap that starts it to the tap
            // that commits it.
            icon: Icons.send_rounded,
            onPressed: ready ? onSend : null,
          ),
        ],
      ),
    );
  }
}
