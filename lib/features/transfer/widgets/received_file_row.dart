import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/transfer.dart';
import '../../../core/services/open_service.dart';
import '../../../core/utils/formatters.dart';
import '../../selection/widgets/file_card.dart';

/// One file in a transfer, in both of the places a person meets one: the
/// screen it arrived on, and history.
///
/// Tapping opens it in whatever app this device already uses for its kind - a
/// photo in the gallery, a PDF in the reader, a song in the music player. The
/// app does not decide that and does not keep a list of what it can handle; it
/// says what the file is and lets the system choose.
///
/// A row that cannot be opened - a file this device sent, a transfer that
/// never finished, a history entry from before the app kept the handle - draws
/// as a plain line with no affordance rather than a tap that does nothing.
class ReceivedFileRow extends StatelessWidget {
  const ReceivedFileRow({
    super.key,
    required this.file,
    this.thumbnailSize = 30,
  });

  final TransferFile file;
  final double thumbnailSize;

  Future<void> _open(BuildContext context) async {
    // Taken before the await: the row may be gone by the time the OS answers.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (await OpenService.open(file)) return;

    // Worth saying out loud. Silence here reads as the app being broken, when
    // in fact there is simply nothing installed that opens this kind of file.
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Could not open ${file.name}. It may have been moved, or nothing '
          'on this device opens this kind of file.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool openable = OpenService.canOpen(file);

    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.xs,
        vertical: Insets.xs,
      ),
      child: Row(
        children: <Widget>[
          FileThumbnail(file: file, size: thumbnailSize),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Text(
              file.name,
              style: context.text.bodySmall?.copyWith(color: c.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Insets.sm),
          Text(
            Formatters.bytes(file.size),
            style: context.text.bodySmall?.copyWith(color: c.textTertiary),
          ),
          if (openable) ...<Widget>[
            const SizedBox(width: Insets.sm),
            Icon(Icons.open_in_new_rounded, size: 15, color: c.textTertiary),
          ],
        ],
      ),
    );

    if (!openable) return row;

    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(Radii.xs),
      child: row,
    );
  }
}
