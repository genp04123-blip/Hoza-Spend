import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/transfer.dart';
import '../../../core/services/reveal_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/hoza_card.dart';
import '../../../shared/widgets/pill_button.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../transfer/widgets/received_file_row.dart';

/// One past transfer, and everything that was in it.
///
/// Closed it stays a log line: name, direction, device, when, size, outcome.
/// Tapping opens it out to every file the transfer carried, because "4 files"
/// is the one thing a person cannot check any other way once the transfer is
/// over - the folder only tells them what is on disk now, not what arrived
/// together.
class HistoryTile extends StatefulWidget {
  const HistoryTile({super.key, required this.record, this.onDelete});

  final TransferRecord record;

  /// Asked to take this entry away - and, for a received transfer, the files
  /// it left on this device. Null hides the button.
  final VoidCallback? onDelete;

  @override
  State<HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<HistoryTile> {
  bool _open = false;

  TransferRecord get _record => widget.record;

  bool get _sent => _record.direction == TransferDirection.send;

  /// The saved path of the first received file, when there is one to open.
  String? get _openablePath {
    if (_sent || _record.status != TransferStatus.completed) return null;
    if (!RevealService.isSupported) return null;
    for (final TransferFile file in _record.files) {
      if (file.savedPath case final String path) return path;
    }
    return null;
  }

  String get _title {
    if (_record.files.length == 1) return _record.files.first.name;
    return '${_record.files.length} files';
  }

  (String, StatusTone) get _outcome => switch (_record.status) {
        TransferStatus.completed => (
            _sent ? 'Sent' : 'Received',
            StatusTone.positive,
          ),
        TransferStatus.cancelled => ('Cancelled', StatusTone.neutral),
        TransferStatus.rejected => ('Declined', StatusTone.warning),
        _ => ('Failed', StatusTone.negative),
      };

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final (String label, StatusTone tone) = _outcome;

    return HozaCard(
      radius: Radii.md,
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.sm,
      ),
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: BorderRadius.circular(Radii.xs),
                ),
                child: Icon(
                  _sent ? Icons.north_east_rounded : Icons.south_west_rounded,
                  size: 17,
                  color: _record.status == TransferStatus.completed
                      ? (_sent ? c.primary : c.success)
                      : c.textTertiary,
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _title,
                      style: context.text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_sent ? 'To' : 'From'} ${_record.deviceName} - '
                      '${Formatters.bytes(_record.totalBytes)} - '
                      '${Formatters.timestamp(_record.startedAt)}',
                      style: context.text.bodySmall
                          ?.copyWith(color: c.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Insets.sm),
              StatusPill(label: label, tone: tone),
              // Right on the row rather than hidden in the opened half: the
              // one thing a person comes to a log line to do, besides read it,
              // is get rid of it. Danger-toned so it is never mistaken for
              // the arrow beside it.
              if (widget.onDelete case final VoidCallback onDelete) ...<Widget>[
                const SizedBox(width: Insets.sm),
                PillButton(
                  icon: Icons.delete_outline_rounded,
                  tone: c.danger,
                  tooltip: 'Delete',
                  onPressed: onDelete,
                ),
              ],
              const SizedBox(width: Insets.xs),
              // Turns over as the row opens, so the arrow is the state rather
              // than a decoration that happens to point somewhere.
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: context.motion(Motion.fast),
                curve: Motion.standard,
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: context.motion(Motion.normal),
            curve: Motion.standard,
            alignment: Alignment.topCenter,
            child: _open
                ? _Details(record: _record, folder: _openablePath)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// The opened-out half: every file in the transfer, why it failed if it did,
/// and the way back to the folder.
class _Details extends StatelessWidget {
  const _Details({required this.record, required this.folder});

  final TransferRecord record;
  final String? folder;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Padding(
      padding: const EdgeInsets.only(top: Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Divider(color: c.border, height: 1),
          const SizedBox(height: Insets.md),
          // Each received file opens where it belongs - the gallery, the PDF
          // reader, whatever this device uses for its kind. History is the
          // only place a file from three transfers ago can still be reached
          // by name, so the row that names it is the row that opens it.
          for (int i = 0; i < record.files.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == record.files.length - 1 ? 0 : Insets.xs,
              ),
              child: ReceivedFileRow(file: record.files[i]),
            ),

          // Kept for the opened view only. A failure reason is worth reading
          // once, not worth repeating on every line of a scrolling log.
          if (record.failureReason case final String reason) ...<Widget>[
            const SizedBox(height: Insets.md),
            Text(
              reason,
              style: context.text.bodySmall?.copyWith(color: c.danger),
            ),
          ],

          if (folder case final String path) ...<Widget>[
            const SizedBox(height: Insets.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: PillButton(
                icon: Icons.folder_open_rounded,
                label: 'Open folder',
                // Quieter than the Open on each file above it. Both are ways
                // in, but one lands on the file and the other only near it.
                tone: c.textSecondary,
                onPressed: () => RevealService.openContainingFolder(path),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
