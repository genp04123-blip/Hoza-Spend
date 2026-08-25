import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';

/// The six digit session code, one digit per box.
///
/// Shown on both devices so the user can see the two screens match before
/// accepting. It is a confirmation aid, not a password: the real protection is
/// that a human has to press Accept.
class SessionCodeView extends StatelessWidget {
  const SessionCodeView({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    if (code.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < code.length; i++)
          Padding(
            padding: EdgeInsets.only(right: i == code.length - 1 ? 0 : Insets.sm),
            child: Container(
              width: 40,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: c.border),
              ),
              child: Text(
                code[i],
                style: context.text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  // Tabular-ish spacing so the row does not shuffle between
                  // narrow and wide digits.
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
