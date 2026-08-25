import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../data/local/storage_service.dart';
import '../../../shared/widgets/hoza_buttons.dart';
import '../../../shared/widgets/hoza_card.dart';
import '../../../shared/widgets/hoza_sheet.dart';
import '../../settings/settings_controller.dart';

/// Shown once, on the first launch that reaches the home screen: where received
/// files are saved, and an offer to make the folder now.
///
/// Worth a moment of the user's time because "it went to Downloads" is the
/// single most common thing someone needs to know after a transfer, and the
/// worst time to go looking for it is while wondering whether the transfer
/// worked at all.
Future<void> showFolderSetupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (BuildContext sheetContext) => const _FolderSetupSheet(),
  );
}

class _FolderSetupSheet extends StatefulWidget {
  const _FolderSetupSheet();

  @override
  State<_FolderSetupSheet> createState() => _FolderSetupSheetState();
}

class _FolderSetupSheetState extends State<_FolderSetupSheet> {
  bool _working = false;
  bool _closing = false;

  Future<void> _create() async {
    if (_working || _closing) return;
    setState(() => _working = true);

    final SettingsController settings = context.read<SettingsController>();
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool created = await StorageService.createDownloadFolder();
    await settings.markFolderPrepared();
    if (!mounted) return;

    _closing = true;
    navigator.pop();
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            created
                // Android 10+ cannot pre-create it, and saying so plainly beats
                // a success message for something that did not happen.
                ? 'Folder ready: Downloads/${StorageService.folderName}'
                : 'The folder will appear with your first received file.',
          ),
        ),
      );
  }

  Future<void> _dismiss() async {
    if (_working || _closing) return;
    _closing = true;
    await context.read<SettingsController>().markFolderPrepared();
    if (mounted) Navigator.of(context).pop();
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
              icon: Icons.folder_open_rounded,
              color: c.primary,
              background: c.primarySoft,
            ),
          ),
          const SizedBox(height: Insets.xl),
          Text(
            'Where your files will go',
            textAlign: TextAlign.center,
            style: context.text.headlineSmall,
          ),
          const SizedBox(height: Insets.sm),
          Text(
            'Everything you receive is saved into a HozaSend folder inside '
            'your Downloads.',
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Insets.xl),
          HozaCard(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.lg,
              vertical: Insets.md,
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.folder_rounded, size: 20, color: c.primary),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Text(
                    'Downloads / ${StorageService.folderName}',
                    style: context.text.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.xl),
          HozaPrimaryButton(
            label: _working ? 'Creating...' : 'Create folder',
            icon: Icons.create_new_folder_rounded,
            onPressed: _working ? null : _create,
          ),
          const SizedBox(height: Insets.md),
          HozaSecondaryButton(
            label: 'Not now',
            onPressed: _working ? null : _dismiss,
          ),
        ],
      ),
    );
  }
}
