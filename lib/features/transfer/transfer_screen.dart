import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/models/transfer.dart';
import '../../core/services/open_service.dart';
import '../../core/services/reveal_service.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/hoza_background.dart';
import '../../shared/widgets/hoza_buttons.dart';
import '../../shared/widgets/hoza_card.dart';
import '../../shared/widgets/hoza_sheet.dart';
import '../../shared/widgets/progress_bar.dart';
import '../../shared/widgets/success_check.dart';
import '../selection/selection_controller.dart';
import '../selection/widgets/file_card.dart';
import 'transfer_controller.dart';
import 'widgets/received_file_row.dart';
import 'widgets/transfer_flight.dart';

/// Live transfer: what is moving, how fast, and how much longer.
///
/// The same screen serves both directions. Only the wording changes, because
/// the numbers a user wants are identical either way.
class TransferScreen extends StatelessWidget {
  const TransferScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TransferController transfer = context.watch<TransferController>();

    return PopScope(
      // Leaving mid-transfer would hide a running operation with no way back.
      // Cancelling is a button, not an accident.
      canPop: !transfer.isActive,
      child: Scaffold(
        body: HozaBackground(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.pagePadding,
                    vertical: Insets.xxl,
                  ),
                  child: transfer.hasTransfer
                      ? _TransferBody(transfer: transfer)
                      : const _NothingRunning(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NothingRunning extends StatelessWidget {
  const _NothingRunning();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text('No transfer running', style: context.text.headlineSmall),
        const SizedBox(height: Insets.xl),
        HozaSecondaryButton(
          label: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

class _TransferBody extends StatelessWidget {
  const _TransferBody({required this.transfer});

  final TransferController transfer;

  String get _verb => transfer.isSending ? 'Sending' : 'Receiving';

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final TransferProgress progress = transfer.progress;
    final bool done = transfer.status.isFinished;

    final Widget running = Column(
      key: const ValueKey<String>('running'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          transfer.status == TransferStatus.awaitingApproval
              ? 'Waiting for ${transfer.deviceName ?? 'the other device'}'
              : _verb,
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: Insets.sm),
        Text(
          progress.currentFileName ?? _fileSummary(transfer),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.text.headlineSmall,
        ),
        const SizedBox(height: Insets.section),
        // Counted rather than snapped. The figure changes ten times a second,
        // and a number that ticks reads as one moving thing instead of ten.
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: progress.percent.toDouble()),
          duration: const Duration(milliseconds: 110),
          curve: Curves.linear,
          builder: (BuildContext context, double shown, Widget? child) => Text(
            '${shown.round()}%',
            textAlign: TextAlign.center,
            style: context.text.displayLarge,
          ),
        ),
        const SizedBox(height: Insets.lg),
        HozaProgressBar(
          value: progress.fraction,
          active: transfer.isActive,
        ),
        const SizedBox(height: Insets.lg),
        _Stats(progress: progress),
      ],
    );

    final bool ok = transfer.status == TransferStatus.completed;
    final String peer = transfer.deviceName ?? 'the other device';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The route stays on screen from the first byte to the last, so the
        // outcome lands on the same picture the user was watching rather than
        // replacing it. Sender is always on the left.
        TransferFlight(
          fromLabel: transfer.isSending ? 'This device' : peer,
          toLabel: transfer.isSending ? peer : 'This device',
          fromIcon: transfer.isSending
              ? Icons.folder_rounded
              : Icons.devices_rounded,
          toIcon: transfer.isSending
              ? Icons.devices_rounded
              : Icons.folder_rounded,
          active: transfer.isActive &&
              transfer.status != TransferStatus.awaitingApproval,
          complete: ok,
          failed: done && !ok,
        ),
        const SizedBox(height: Insets.xl),

        // Finishing is the biggest state change in the app, so the numbers
        // hand over to the outcome instead of being replaced by it.
        AnimatedSwitcher(
          duration: context.motion(Motion.slow),
          switchInCurve: Motion.standard,
          switchOutCurve: Motion.exit,
          // Passthrough keeps the progress bar full width; the default loose
          // stack would let this column shrink to its widest line of text.
          layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
            alignment: Alignment.center,
            fit: StackFit.passthrough,
            children: <Widget>[...previous, ?current],
          ),
          child: done
              ? Center(
                  key: const ValueKey<String>('outcome'),
                  child: _Outcome(transfer: transfer),
                )
              : running,
        ),

        // What arrived, and the way into it. A received file is only worth
        // anything once it is open, and this is the one moment the user is
        // looking straight at it - sending them off to find it in a file
        // manager is the app stopping a step short of the job.
        if (ok && !transfer.isSending) ...<Widget>[
          const SizedBox(height: Insets.lg),
          Flexible(child: _ReceivedFiles(files: transfer.files)),
        ],

        const SizedBox(height: Insets.section),
        _Actions(transfer: transfer),
      ],
    );
  }

  static String _fileSummary(TransferController transfer) {
    final int count = transfer.files.length;
    if (count == 1) return transfer.files.first.name;
    return '$count files';
  }
}

/// The files that just landed, each one a way into itself.
///
/// Scrolls inside its own box rather than growing the page: a transfer can
/// carry forty files, and the outcome and the Done button have to stay where
/// the user left them.
class _ReceivedFiles extends StatelessWidget {
  const _ReceivedFiles({required this.files});

  final List<TransferFile> files;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    if (files.isEmpty) return const SizedBox.shrink();

    // Only promised when it is true. On a phone where a file could not be
    // published there is nothing to tap, and an instruction that does nothing
    // is worse than no instruction.
    final bool anyOpenable = files.any(OpenService.canOpen);

    return HozaCard(
      radius: Radii.md,
      padding: const EdgeInsets.all(Insets.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (anyOpenable) ...<Widget>[
            Text(
              files.length == 1 ? 'Tap to open it' : 'Tap a file to open it',
              style: context.text.labelSmall?.copyWith(color: c.textTertiary),
            ),
            const SizedBox(height: Insets.sm),
          ],
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: files.length,
              itemBuilder: (BuildContext context, int i) => Padding(
                padding: EdgeInsets.only(
                  bottom: i == files.length - 1 ? 0 : Insets.xs,
                ),
                child: ReceivedFileRow(file: files[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.progress});

  final TransferProgress progress;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final TextStyle? meta =
        context.text.bodyMedium?.copyWith(color: c.textSecondary);

    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              '${Formatters.bytes(progress.bytesTransferred)} / '
              '${Formatters.bytes(progress.totalBytes)}',
              style: meta,
            ),
            Text(
              progress.isPaused
                  ? 'Paused'
                  : Formatters.speed(progress.bytesPerSecond),
              style: meta,
            ),
          ],
        ),
        const SizedBox(height: Insets.sm),
        Text(
          // A held transfer has no estimate worth showing: the wait is a
          // decision, and counting it down as though the network had slowed
          // would be inventing a number.
          progress.isPaused
              ? 'Waiting to continue'
              : Formatters.eta(progress.remaining),
          style: context.text.bodySmall?.copyWith(color: c.textTertiary),
        ),
        if (progress.filesTotal > 1) ...<Widget>[
          const SizedBox(height: Insets.sm),
          Text(
            'File ${progress.filesDone + 1} of ${progress.filesTotal}',
            style: context.text.bodySmall?.copyWith(color: c.textTertiary),
          ),
        ],
      ],
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({required this.transfer});

  final TransferController transfer;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool ok = transfer.status == TransferStatus.completed;
    final int count = transfer.files.length;
    final String noun = count == 1 ? 'file' : 'files';

    final String title = switch (transfer.status) {
      TransferStatus.completed =>
        transfer.isSending ? 'Sent successfully' : 'Received $count $noun',
      TransferStatus.cancelled => 'Transfer cancelled',
      TransferStatus.rejected => 'Transfer declined',
      _ => 'Transfer failed',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Success draws itself; anything else gets the calm static badge,
        // because a flourish on a failure celebrates the wrong thing.
        if (ok)
          const HozaSuccessCheck()
        else
          SheetBadge(
            icon: Icons.error_outline_rounded,
            color: c.danger,
            background: c.dangerSoft,
          ),
        const SizedBox(height: Insets.xl),
        Text(title, textAlign: TextAlign.center, style: context.text.headlineMedium),
        if (ok && transfer.deviceName != null) ...<Widget>[
          const SizedBox(height: Insets.sm),
          Text(
            transfer.isSending
                ? 'Delivered to ${transfer.deviceName}'
                : 'From ${transfer.deviceName}',
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
          ),
        ],
        if (!ok && transfer.error != null) ...<Widget>[
          const SizedBox(height: Insets.sm),
          Text(
            transfer.error!.message,
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
          ),
        ],
        if (ok && !transfer.isSending && transfer.files.isNotEmpty) ...<Widget>[
          const SizedBox(height: Insets.xl),
          HozaCard(
            padding: const EdgeInsets.all(Insets.md),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < transfer.files.length && i < 4; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i == transfer.files.length - 1 ? 0 : Insets.md,
                    ),
                    child: Row(
                      children: <Widget>[
                        FileThumbnail(file: transfer.files[i], size: 36),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: Text(
                            transfer.files[i].name,
                            style: context.text.bodyMedium
                                ?.copyWith(color: c.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (transfer.files.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: Insets.sm),
                    child: Text(
                      'and ${transfer.files.length - 4} more',
                      style: context.text.bodySmall
                          ?.copyWith(color: c.textTertiary),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.transfer});

  final TransferController transfer;

  void _finish(BuildContext context) {
    // The queue has done its job; leaving it filled would offer to send the
    // same files again the next time the screen opens.
    if (transfer.isSending &&
        transfer.status == TransferStatus.completed) {
      context.read<SelectionController>().clear();
    }
    transfer.reset();
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  /// The file that just arrived, when exactly one did and this device can open
  /// it.
  ///
  /// Only for a single file. With several, the list above is where they open
  /// from - one button at the bottom of the screen cannot say which one it
  /// means.
  TransferFile? get _singleReceivedFile {
    if (transfer.isSending || transfer.status != TransferStatus.completed) {
      return null;
    }
    if (transfer.files.length != 1) return null;
    final TransferFile file = transfer.files.first;
    return OpenService.canOpen(file) ? file : null;
  }

  /// The folder the received files landed in, when this platform can open one.
  String? get _savedFolder {
    if (transfer.isSending || transfer.status != TransferStatus.completed) {
      return null;
    }
    if (!RevealService.isSupported) return null;
    for (final TransferFile file in transfer.files) {
      if (file.savedPath case final String path) return path;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (transfer.isActive) {
      final bool paused = transfer.isPaused;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Offered only once bytes are moving. While the other device is
          // still deciding whether to accept there is nothing to hold, and a
          // button that does nothing is worse than no button.
          if (transfer.canPause || paused) ...<Widget>[
            HozaSecondaryButton(
              label: paused ? 'Resume' : 'Pause',
              icon: paused
                  ? Icons.play_arrow_rounded
                  : Icons.pause_rounded,
              onPressed: paused ? transfer.resume : transfer.pause,
            ),
            const SizedBox(height: Insets.md),
          ],
          HozaSecondaryButton(
            label: 'Cancel',
            icon: Icons.close_rounded,
            onPressed: transfer.cancel,
          ),
        ],
      );
    }

    final String? folder = _savedFolder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (transfer.canRetry) ...<Widget>[
          HozaPrimaryButton(
            label: 'Try Again',
            icon: Icons.refresh_rounded,
            onPressed: () => unawaited(transfer.retry()),
          ),
          const SizedBox(height: Insets.md),
          HozaSecondaryButton(
            label: 'Close',
            onPressed: () => _finish(context),
          ),
        ] else ...<Widget>[
          HozaPrimaryButton(
            label: 'Done',
            icon: Icons.check_rounded,
            onPressed: () => _finish(context),
          ),
          // The next thing a person wants after receiving one file is to look
          // at it, and until now the only way was to go and find it.
          if (_singleReceivedFile case final TransferFile file) ...<Widget>[
            const SizedBox(height: Insets.md),
            HozaSecondaryButton(
              label: 'Open File',
              icon: Icons.open_in_new_rounded,
              onPressed: () => unawaited(openReceivedFile(context, file)),
            ),
          ],
          if (folder != null) ...<Widget>[
            const SizedBox(height: Insets.md),
            HozaSecondaryButton(
              label: 'Open folder',
              icon: Icons.folder_open_rounded,
              onPressed: () =>
                  unawaited(RevealService.openContainingFolder(folder)),
            ),
          ],
        ],
      ],
    );
  }
}
