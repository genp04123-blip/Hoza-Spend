import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/device_identity.dart';
import '../../shared/widgets/fade_slide_in.dart';
import '../../shared/widgets/hoza_buttons.dart';
import '../../shared/widgets/hoza_logo.dart';
import '../../shared/widgets/hoza_text_field.dart';
import '../settings/settings_controller.dart';
import 'widgets/intro_backdrop.dart';

/// First launch: name this device.
///
/// The field is pre-filled with the phone model or PC name and pre-selected, so
/// the fastest path through this screen is a single tap on Continue.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _field = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final String suggestion = await DeviceIdentity.suggestName();
    if (!mounted || _field.text.trim().isNotEmpty) return;
    _field.value = TextEditingValue(
      text: suggestion,
      // Selected rather than just placed, so typing replaces it in one go.
      selection: TextSelection(baseOffset: 0, extentOffset: suggestion.length),
    );
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final String name = _field.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    await context.read<SettingsController>().setDeviceName(name);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Scaffold(
      body: IntroBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: context.pagePadding,
                vertical: Insets.section,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    FadeSlideIn(
                      child: Center(child: HozaLogo(size: 76)),
                    ),
                    const SizedBox(height: Insets.xl),
                    FadeSlideIn(
                      index: 1,
                      child: Text(
                        AppConstants.appName,
                        textAlign: TextAlign.center,
                        style: context.text.displayMedium,
                      ),
                    ),
                    const SizedBox(height: Insets.section),

                    FadeSlideIn(
                      index: 2,
                      child: Text(
                        'What should we call this device?',
                        textAlign: TextAlign.center,
                        style: context.text.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: Insets.sm),
                    FadeSlideIn(
                      index: 3,
                      child: Text(
                        'Nearby devices will see this name when you share.',
                        textAlign: TextAlign.center,
                        style: context.text.bodyMedium
                            ?.copyWith(color: c.textSecondary),
                      ),
                    ),
                    const SizedBox(height: Insets.xxl),

                    FadeSlideIn(
                      index: 4,
                      child: HozaTextField(
                        controller: _field,
                        hintText: "Rayan's S24 Ultra",
                        prefixIcon: Icons.badge_outlined,
                        maxLength: DeviceIdentity.maxNameLength,
                        autofocus: true,
                        onSubmitted: (_) => _continue(),
                      ),
                    ),
                    const SizedBox(height: Insets.xl),

                    FadeSlideIn(
                      index: 5,
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _field,
                        builder: (
                          BuildContext context,
                          TextEditingValue value,
                          Widget? child,
                        ) {
                          final bool ready =
                              value.text.trim().isNotEmpty && !_saving;
                          return HozaPrimaryButton(
                            label: 'Continue',
                            icon: Icons.arrow_forward_rounded,
                            onPressed: ready ? _continue : null,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: Insets.lg),

                    FadeSlideIn(
                      index: 6,
                      child: Text(
                        'You can change it later in Settings.',
                        textAlign: TextAlign.center,
                        style: context.text.bodySmall
                            ?.copyWith(color: c.textTertiary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
