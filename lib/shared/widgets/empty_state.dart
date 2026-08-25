import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import 'hoza_card.dart';

/// A designed empty state, not a bare sentence.
///
/// Every one answers the same three questions the guide calls for: what
/// happened, why, and what the user can do about it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return HozaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.xl,
        vertical: Insets.xl,
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.primarySoft,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Icon(icon, color: c.primary, size: 21),
          ),
          const SizedBox(height: Insets.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.text.titleMedium,
          ),
          const SizedBox(height: Insets.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: Insets.xl),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: c.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.xl,
                  vertical: Insets.md,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                backgroundColor: c.primarySoft,
              ),
              child: Text(
                actionLabel!,
                style: context.text.labelLarge?.copyWith(color: c.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
