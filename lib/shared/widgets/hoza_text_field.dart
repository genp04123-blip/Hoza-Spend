import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';

/// The app's single text input. Wraps [TextField] so focus colours, radius and
/// padding come from the theme rather than being restated at each call site.
class HozaTextField extends StatelessWidget {
  const HozaTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.maxLength,
    this.autofocus = false,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.prefixIcon,
  });

  final TextEditingController controller;
  final String? hintText;
  final int? maxLength;
  final bool autofocus;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: context.text.bodyLarge,
      cursorColor: context.colors.primary,
      // Hard-capped rather than validated after the fact, so the user cannot
      // type a name the beacon would have to truncate.
      inputFormatters: maxLength == null
          ? null
          : <TextInputFormatter>[LengthLimitingTextInputFormatter(maxLength)],
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, size: 20, color: context.colors.textTertiary),
      ),
    );
  }
}
