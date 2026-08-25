import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/app_settings.dart';
import '../../core/services/device_identity.dart';
import '../../data/local/storage_service.dart';
import '../../shared/widgets/fade_slide_in.dart';
import '../../shared/widgets/hoza_app_bar.dart';
import '../../shared/widgets/hoza_background.dart';
import '../../shared/widgets/hoza_segmented.dart';
import '../../shared/widgets/hoza_text_field.dart';
import '../../shared/widgets/settings_tile.dart';
import 'settings_controller.dart';
import 'widgets/guide_section.dart';

/// Settings, kept to the six things the specification asks for.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsController controller = context.watch<SettingsController>();
    final AppSettings s = controller.settings;
    final AppColors c = context.colors;

    return Scaffold(
      body: HozaBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              const HozaAppBar(title: 'Settings'),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        context.pagePadding,
                        Insets.lg,
                        context.pagePadding,
                        Insets.section,
                      ),
                      children: <Widget>[
                        FadeSlideIn(
                          child: SettingsGroup(
                            title: 'Device',
                            children: <Widget>[
                              SettingsTile(
                                icon: Icons.badge_outlined,
                                title: 'Device name',
                                subtitle: s.deviceName,
                                onTap: () => _rename(context, controller),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: Insets.xxl),

                        FadeSlideIn(
                          index: 1,
                          child: SettingsGroup(
                            title: 'Appearance',
                            children: <Widget>[
                              Padding(
                                padding: const EdgeInsets.all(Insets.lg),
                                child: HozaSegmented<ThemeMode>(
                                  selected: s.themeMode,
                                  onChanged: controller.setThemeMode,
                                  options: const <SegmentOption<ThemeMode>>[
                                    SegmentOption<ThemeMode>(
                                      value: ThemeMode.system,
                                      label: 'System',
                                      icon: Icons.brightness_auto_rounded,
                                    ),
                                    SegmentOption<ThemeMode>(
                                      value: ThemeMode.light,
                                      label: 'Light',
                                      icon: Icons.light_mode_rounded,
                                    ),
                                    SegmentOption<ThemeMode>(
                                      value: ThemeMode.dark,
                                      label: 'Dark',
                                      icon: Icons.dark_mode_rounded,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: Insets.xxl),

                        FadeSlideIn(
                          index: 2,
                          child: SettingsGroup(
                            title: 'Transfers',
                            children: <Widget>[
                              SettingsTile(
                                icon: Icons.folder_outlined,
                                title: 'Download location',
                                // Where the files actually end up, which on
                                // Android is not the path the app writes to.
                                subtitle: StorageService.userFacingLocation(
                                  s.downloadPath,
                                ),
                                onTap: controller.canChooseDownloadPath
                                    ? controller.chooseDownloadPath
                                    : null,
                              ),
                              SettingsSwitchTile(
                                icon: Icons.bolt_rounded,
                                title: 'Auto accept',
                                subtitle: 'Receive files without confirming '
                                    'each one. Only turn this on at home.',
                                value: s.autoAccept,
                                onChanged: controller.setAutoAccept,
                              ),
                              SettingsSwitchTile(
                                icon: Icons.notifications_none_rounded,
                                title: 'Notifications',
                                subtitle: 'Alert me about incoming and '
                                    'completed transfers.',
                                value: s.notificationsEnabled,
                                onChanged: controller.setNotificationsEnabled,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: Insets.xxl),

                        const FadeSlideIn(
                          index: 3,
                          child: GuideSection(),
                        ),
                        const SizedBox(height: Insets.xxl),

                        FadeSlideIn(
                          index: 4,
                          child: SettingsGroup(
                            title: 'About',
                            children: <Widget>[
                              SettingsTile(
                                icon: Icons.help_outline_rounded,
                                title: 'How it works',
                                subtitle: 'Replay the introduction',
                                onTap: () => Navigator.of(context)
                                    .pushNamed(AppRoutes.intro),
                              ),
                              SettingsTile(
                                icon: Icons.info_outline_rounded,
                                title: AppConstants.appName,
                                subtitle: 'Version ${AppConstants.appVersion}',
                              ),
                              const SettingsTile(
                                icon: Icons.person_outline_rounded,
                                title: 'Developer',
                                subtitle: AppConstants.developerName,
                              ),
                              SettingsTile(
                                icon: Icons.mail_outline_rounded,
                                title: 'Contact',
                                subtitle: AppConstants.developerEmail,
                                // Copies rather than opening a mail client:
                                // launching one needs a plugin, and a copied
                                // address works even where no client is set up.
                                trailing: Icon(
                                  Icons.copy_rounded,
                                  size: 18,
                                  color: c.textTertiary,
                                ),
                                onTap: () => _copyEmail(context),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  Insets.lg,
                                  Insets.lg,
                                  Insets.lg,
                                  Insets.lg,
                                ),
                                child: Text(
                                  'HozaSend moves files straight between '
                                  'devices on your Wi-Fi or hotspot. Nothing '
                                  'is uploaded, no account is needed, and it '
                                  'keeps working with no internet at all.',
                                  style: context.text.bodySmall
                                      ?.copyWith(color: c.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyEmail(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      const ClipboardData(text: AppConstants.developerEmail),
    );
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('Email address copied')),
      );
  }

  Future<void> _rename(
    BuildContext context,
    SettingsController controller,
  ) async {
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _RenameDialog(initialName: controller.deviceName),
    );
    if (result != null) await controller.setDeviceName(result);
  }
}

/// Renaming this device.
///
/// A widget rather than an inline builder specifically so it can own its
/// [TextEditingController]. Creating one beside `showDialog` and disposing it
/// when the future returns throws: the route is still animating out at that
/// point, and the field inside it rebuilds against a controller that no longer
/// exists. Owning it here means dispose runs once the route is actually gone.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _field =
      TextEditingController(text: widget.initialName)
        // Selected rather than just placed, so typing replaces the old name in
        // one go instead of appending to it.
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initialName.length,
        );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _save() {
    final String name = _field.text.trim();
    // Guarded here as well as in the controller: an empty name would otherwise
    // close the dialog looking successful while nothing changed.
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return AlertDialog(
      backgroundColor: c.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      title: Text('Device name', style: context.text.headlineSmall),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'This is how you appear to nearby devices.',
            style: context.text.bodySmall?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Insets.lg),
          HozaTextField(
            controller: _field,
            autofocus: true,
            maxLength: DeviceIdentity.maxNameLength,
            onSubmitted: (String value) => _save(),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: c.textSecondary),
          child: const Text('Cancel'),
        ),
        // Watches the field so Save greys out on an empty name rather than
        // being a button that silently does nothing.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _field,
          builder: (
            BuildContext context,
            TextEditingValue value,
            Widget? child,
          ) {
            return TextButton(
              onPressed: value.text.trim().isEmpty ? null : _save,
              style: TextButton.styleFrom(
                foregroundColor: c.primary,
                disabledForegroundColor: c.textTertiary,
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
              child: const Text('Save'),
            );
          },
        ),
      ],
    );
  }
}
