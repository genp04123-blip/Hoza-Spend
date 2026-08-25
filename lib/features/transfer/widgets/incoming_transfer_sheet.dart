import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/transfer.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/hoza_buttons.dart';
import '../../../shared/widgets/hoza_card.dart';
import '../../../shared/widgets/hoza_sheet.dart';
import '../../selection/widgets/file_card.dart';
import '../transfer_controller.dart';

/// Asks whether to accept files another device is offering.
Future<void> showIncomingTransferSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // Answering has to be deliberate. Tapping away must not silently decline,
    // or leave the sender waiting on nothing.
    isDismissible: false,
    enableDrag: false,
    builder: (BuildContext sheetContext) => const _IncomingTransferSheet(),
  );
}

class _IncomingTransferSheet extends StatefulWidget {
  const _IncomingTransferSheet();

  @override
  State<_IncomingTransferSheet> createState() => _IncomingTransferSheetState();
}

class _IncomingTransferSheetState extends State<_IncomingTransferSheet> {
  static const int _previewLimit = 3;

  bool _closing = false;

  void _close([VoidCallback? action]) {
    if (_closing) return;
    _closing = true;
    action?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final TransferController transfer = context.watch<TransferController>();
    final PendingOffer? offer = transfer.incomingOffer;

    // Resolved without this user: it timed out, or the sender gave up.
    if (offer == null) {
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
      return const SizedBox.shrink();
    }

    final int count = offer.files.length;

    return HozaSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: SheetBadge(
              // Matches Receive everywhere else: the button on home, and the
              // beacon on the receive screen.
              icon: Icons.download_rounded,
              color: c.primary,
              background: c.primarySoft,
            ),
          ),
          const SizedBox(height: Insets.xl),
          Text(
            count == 1 ? 'Incoming file' : 'Incoming $count files',
            textAlign: TextAlign.center,
            style: context.text.headlineSmall,
          ),
          const SizedBox(height: Insets.sm),
          Text(
            'From ${offer.deviceName} - '
            '${Formatters.bytes(offer.totalBytes)}',
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Insets.xl),
          HozaCard(
            padding: const EdgeInsets.all(Insets.md),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < count && i < _previewLimit; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i == count - 1 ? 0 : Insets.md,
                    ),
                    child: _OfferedFile(file: offer.files[i]),
                  ),
                if (count > _previewLimit)
                  Padding(
                    padding: const EdgeInsets.only(top: Insets.md),
                    child: Text(
                      'and ${count - _previewLimit} more',
                      style:
                          context.text.bodySmall?.copyWith(color: c.textTertiary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Insets.xl),
          HozaPrimaryButton(
            label: 'Accept',
            icon: Icons.check_rounded,
            onPressed: () => _close(offer.accept),
          ),
          const SizedBox(height: Insets.md),
          HozaSecondaryButton(
            label: 'Reject',
            onPressed: () => _close(offer.reject),
          ),
        ],
      ),
    );
  }
}

class _OfferedFile extends StatelessWidget {
  const _OfferedFile({required this.file});

  final TransferFile file;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Row(
      children: <Widget>[
        // No source yet - these files are still on the other device - so this
        // always renders the kind icon rather than a preview.
        FileThumbnail(file: file, size: 38),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                file.name,
                style: context.text.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                Formatters.bytes(file.size),
                style: context.text.bodySmall?.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
