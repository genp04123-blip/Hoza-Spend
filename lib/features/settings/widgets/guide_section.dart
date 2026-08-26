import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../data/local/storage_service.dart';
import '../../../shared/widgets/settings_tile.dart';

/// The full guide, in Settings.
///
/// The one thing that decides whether HozaSend works at all - both devices on
/// the same network - is stated at the top and never collapsed. Everything
/// else folds away, because a wall of text in Settings is a wall nobody reads.
class GuideSection extends StatelessWidget {
  const GuideSection({super.key});

  @override
  Widget build(BuildContext context) {
    final String location = StorageService.userFacingLocation(null);

    return SettingsGroup(
      title: 'Guide',
      children: <Widget>[
        const _NetworkRule(),
        // Before the steps, because the steps are useless to someone who
        // has already decided the app is not for their pair of devices. Every
        // combination works, and none of them is a different mode.
        const _GuideEntry(
          icon: Icons.devices_rounded,
          title: 'What it works between',
          lines: <String>[
            'Phone to phone, phone to Windows, or Windows to Windows. It is '
                'the same app on both ends, and the steps below are the same '
                'whichever pair you have.',
            'Either device can send and either can receive. There is no host '
                'and no main device.',
          ],
        ),
        const _GuideEntry(
          icon: Icons.send_rounded,
          title: 'Sending files',
          numbered: true,
          lines: <String>[
            'Open HozaSend on both devices.',
            'Tap the device you want under Nearby devices.',
            'Accept the request on the other device. Check the six digit code '
                'matches on both screens.',
            'Choose your files and tap Send.',
          ],
        ),
        // Placed straight after the steps, because it is the shortest route to
        // the same place and almost nobody finds it on their own: the app has
        // to be opened from inside the app that already has the file.
        _GuideEntry(
          icon: Icons.ios_share_rounded,
          title: 'Sending from another app',
          lines: <String>[
            if (Platform.isAndroid || Platform.isIOS)
              'Share a photo, a document, anything - and pick HozaSend from '
                  'the share sheet. It opens with that file already queued, so '
                  'all that is left is choosing the device.'
            else
              'Right-click a file in Explorer and choose Send to > HozaSend, '
                  'or Send with HozaSend. It opens with that file already '
                  'queued, so all that is left is choosing the device.',
            if (!Platform.isAndroid && !Platform.isIOS)
              'A whole folder works the same way, and so does dropping files '
                  'straight onto the HozaSend window.',
            'Sharing into HozaSend while it is already open adds to what is '
                'queued rather than starting again.',
          ],
        ),
        const _GuideEntry(
          icon: Icons.download_rounded,
          title: 'Receiving files',
          lines: <String>[
            'There is nothing to switch on. HozaSend can be found by nearby '
                'devices whenever it is open.',
            'Tap Receive to see the name other devices will look for, and to '
                'watch for an incoming transfer.',
            'You are always asked before anything is saved, unless you turn on '
                'Auto accept above.',
          ],
        ),
        _GuideEntry(
          icon: Icons.folder_outlined,
          title: 'Where files are saved',
          lines: <String>[
            'Everything you receive goes to $location.',
            if (Platform.isAndroid)
              'On Android 10 and later the folder appears the first time you '
                  'receive something, because Android does not let an app '
                  'create an empty folder there.'
            else if (Platform.isIOS)
              'Open the Files app and look under On My iPhone. iOS has no '
                  'shared Downloads folder, so each app keeps its own - and '
                  'this one is HozaSend.'
            else
              'You can change this in Download location above.',
            'A file is only saved once it has arrived complete and its '
                'contents have been checked, so a failed transfer never leaves '
                'a broken file behind.',
          ],
        ),
        const _GuideEntry(
          icon: Icons.wifi_tethering_rounded,
          title: 'Using a phone hotspot',
          numbered: true,
          lines: <String>[
            "Turn on the phone's hotspot.",
            'Connect the other device to that hotspot.',
            'Open HozaSend on both. They will find each other.',
            'This works with no internet at all - the hotspot only has to '
                'carry the two devices, not a connection.',
            'Android does not allow any app to switch the hotspot on for you, '
                'so that first step has to be done by hand.',
          ],
        ),
        const _GuideEntry(
          icon: Icons.help_outline_rounded,
          title: 'If the devices cannot find each other',
          lines: <String>[
            'Check both are on the same Wi-Fi, or on the same hotspot. Being '
                'on Wi-Fi is not enough if it is a different network.',
            'On Windows, allow HozaSend through the firewall on private '
                'networks. This is the most common cause by far.',
            'Keep HozaSend open on both devices. Discovery stops when the app '
                'is closed or sent to the background.',
            'On Android, keep the screen on while searching. Power saving can '
                'silence the packets HozaSend listens for.',
            'Tap Search again on the home screen to start a fresh scan.',
          ],
        ),
      ],
    );
  }
}

/// The requirement everything else depends on. Deliberately not collapsible.
class _NetworkRule extends StatelessWidget {
  const _NetworkRule();

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      color: c.primarySoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.wifi_rounded, size: 20, color: c.primary),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Both devices must be on the same network',
                  style: context.text.titleSmall?.copyWith(color: c.primary),
                ),
                const SizedBox(height: Insets.xs),
                Text(
                  'The same Wi-Fi, or one device sharing its hotspot with the '
                  'other. HozaSend never uses the internet and never uploads '
                  'anything - it only needs the two devices on one local '
                  'network.',
                  style:
                      context.text.bodySmall?.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One foldable entry. Collapsed by default so the group stays scannable.
class _GuideEntry extends StatefulWidget {
  const _GuideEntry({
    required this.icon,
    required this.title,
    required this.lines,
    this.numbered = false,
  });

  final IconData icon;
  final String title;
  final List<String> lines;

  /// Steps get numbers, facts get dots. The difference tells the reader
  /// whether order matters before they have read a word.
  final bool numbered;

  @override
  State<_GuideEntry> createState() => _GuideEntryState();
}

class _GuideEntryState extends State<_GuideEntry> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsTile(
          icon: widget.icon,
          title: widget.title,
          onTap: () => setState(() => _open = !_open),
          trailing: AnimatedRotation(
            turns: _open ? 0.5 : 0,
            duration: context.motion(Motion.normal),
            curve: Motion.standard,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: c.textTertiary,
            ),
          ),
        ),
        AnimatedSize(
          duration: context.motion(Motion.normal),
          curve: Motion.standard,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.lg,
                    0,
                    Insets.lg,
                    Insets.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (int i = 0; i < widget.lines.length; i++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom:
                                i == widget.lines.length - 1 ? 0 : Insets.md,
                          ),
                          child: _Line(
                            marker: widget.numbered ? '${i + 1}' : null,
                            text: widget.lines[i],
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.marker, required this.text});

  final String? marker;
  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 24,
          child: marker == null
              ? Padding(
                  // Nudged down onto the first line's baseline rather than its
                  // top edge.
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration:
                        BoxDecoration(color: c.primary, shape: BoxShape.circle),
                  ),
                )
              : Text(
                  marker!,
                  style: context.text.labelSmall?.copyWith(
                    color: c.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        Expanded(
          child: Text(
            text,
            style: context.text.bodySmall?.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}
