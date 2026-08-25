import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_tokens.dart';

/// Lets a desktop user drop files straight onto the window.
///
/// On Android this is a pass-through: there is nothing to drop from. Building
/// the drop machinery there would only add a layer for no behaviour.
class FileDropTarget extends StatefulWidget {
  const FileDropTarget({
    super.key,
    required this.child,
    required this.onDropped,
  });

  final Widget child;

  /// Receives the dropped paths. Directories are included; the caller decides
  /// whether to expand them.
  final void Function(List<String> paths) onDropped;

  static bool get isSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  State<FileDropTarget> createState() => _FileDropTargetState();
}

class _FileDropTargetState extends State<FileDropTarget> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    if (!FileDropTarget.isSupported) return widget.child;
    final AppColors c = context.colors;

    return DropTarget(
      onDragEntered: (DropEventDetails details) =>
          setState(() => _hovering = true),
      onDragExited: (DropEventDetails details) =>
          setState(() => _hovering = false),
      onDragDone: (DropDoneDetails details) {
        setState(() => _hovering = false);
        final List<String> paths = <String>[
          for (final XFile file in details.files)
            if (file.path.isNotEmpty) file.path,
        ];
        if (paths.isNotEmpty) widget.onDropped(paths);
      },
      child: Stack(
        children: <Widget>[
          widget.child,
          // Ignores pointers so the drag itself is never intercepted.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _hovering ? 1 : 0,
                duration: Motion.fast,
                child: Container(
                  margin: const EdgeInsets.all(Insets.md),
                  decoration: BoxDecoration(
                    color: c.primarySoft,
                    borderRadius: BorderRadius.circular(Radii.xl),
                    border: Border.all(color: c.primary, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.file_download_outlined,
                        size: 40,
                        color: c.primary,
                      ),
                      const SizedBox(height: Insets.md),
                      Text(
                        'Drop to add',
                        style: context.text.headlineSmall
                            ?.copyWith(color: c.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
