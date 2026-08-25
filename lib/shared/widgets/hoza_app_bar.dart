import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';

/// A quiet app bar: no fill, no elevation, no centring.
///
/// The back affordance is only drawn when there is something to pop, so a root
/// screen never shows a dead arrow.
class HozaAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HozaAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final bool canPop = Navigator.of(context).canPop();
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.pagePadding - Insets.sm,
        vertical: Insets.sm,
      ),
      child: Row(
        children: <Widget>[
          if (canPop)
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
            )
          else
            const SizedBox(width: Insets.sm),
          const SizedBox(width: Insets.xs),
          Expanded(
            child: Text(title, style: context.text.headlineSmall),
          ),
          ...?actions,
        ],
      ),
    );
  }
}
