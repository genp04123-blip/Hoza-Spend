import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/models/transfer.dart';
import '../../core/services/reveal_service.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/fade_slide_in.dart';
import '../../shared/widgets/hoza_app_bar.dart';
import '../../shared/widgets/hoza_background.dart';
import 'history_controller.dart';
import 'widgets/history_tile.dart';

/// Everything this device has sent and received.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  Future<void> _confirmClear(
    BuildContext context,
    HistoryController history,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        title: Text('Clear history?', style: dialogContext.text.headlineSmall),
        content: Text(
          'This only removes the list. Files you have already received stay '
          'where they are.',
          style: dialogContext.text.bodyMedium
              ?.copyWith(color: dialogContext.colors.textSecondary),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: dialogContext.colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Clear',
              style: TextStyle(
                color: dialogContext.colors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await history.clear();
  }

  @override
  Widget build(BuildContext context) {
    final HistoryController history = context.watch<HistoryController>();
    final List<TransferRecord> records = history.records;

    return Scaffold(
      body: HozaBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                children: <Widget>[
                  HozaAppBar(
                    title: 'History',
                    actions: <Widget>[
                      if (records.isNotEmpty)
                        TextButton(
                          onPressed: () => _confirmClear(context, history),
                          style: TextButton.styleFrom(
                            foregroundColor: context.colors.textSecondary,
                          ),
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                  Expanded(
                    child: records.isEmpty
                        ? _empty(context)
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                              context.pagePadding,
                              Insets.sm,
                              context.pagePadding,
                              Insets.section,
                            ),
                            itemCount: records.length,
                            separatorBuilder:
                                (BuildContext context, int index) =>
                                    const SizedBox(height: Insets.md),
                            itemBuilder: (BuildContext context, int index) =>
                                FadeSlideIn(
                              key: ValueKey<String>(records[index].id),
                              // Only the first screenful is staggered; beyond
                              // that the delay would outlast the scroll.
                              index: index < 8 ? index : 0,
                              child: HistoryTile(record: records[index]),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.pagePadding),
        child: EmptyState(
          icon: Icons.history_rounded,
          title: 'No transfers yet',
          message: RevealService.isSupported
              ? 'Files you send and receive will be listed here. Tap a '
                  'received transfer to open its folder.'
              : 'Files you send and receive will be listed here.',
        ),
      ),
    );
  }
}
