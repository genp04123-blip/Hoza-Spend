import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/file_source.dart';
import '../../../core/models/transfer.dart';
import '../../../core/services/android_files.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/hoza_card.dart';

/// One selected file: thumbnail or icon, name, size, remove.
class FileCard extends StatelessWidget {
  const FileCard({super.key, required this.file, this.onRemove});

  final TransferFile file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return HozaCard(
      padding: const EdgeInsets.all(Insets.md),
      child: Row(
        children: <Widget>[
          FileThumbnail(file: file),
          const SizedBox(width: Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  // Its place in the folder it came from, where it has one.
                  // Two files called `notes.txt` from two different folders
                  // are otherwise the same row twice.
                  file.displayName,
                  style: context.text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  Formatters.bytes(file.size),
                  style:
                      context.text.bodySmall?.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: 'Remove',
              color: c.textTertiary,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// A real preview where one is cheap, otherwise a tinted kind icon.
///
/// Three routes, because the platforms hand back different things.
///
/// Where there is a path - the desktops, and iOS, whose picker copies the file
/// into the app first - `Image.file` decodes straight from disk at thumbnail
/// size, and nothing is read that is not drawn.
///
/// Android has a storage-access URI and no path, and asks the provider for a
/// preview it has already made. That is about ten kilobytes, and it covers
/// video as well as stills. Reading the file instead would mean pulling a 6 MB
/// photo across the platform channel for a 46-pixel square, once per card, on
/// a screen that can hold a hundred of them.
///
/// A file with no cheap preview gets its kind icon, which is an answer rather
/// than a failure.
class FileThumbnail extends StatefulWidget {
  const FileThumbnail({super.key, required this.file, this.size = 46});

  /// Images larger than this get an icon instead, where a preview means
  /// reading the file. A preview is never worth pulling many megabytes into
  /// memory for.
  static const int maxPreviewBytes = 6 * 1024 * 1024;

  /// What to ask a provider for. Comfortably above the card at any density,
  /// and small enough that a hundred of them are still a rounding error.
  static const int providerPreviewPixels = 256;

  final TransferFile file;
  final double size;

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  /// Held in state rather than built in `build`, so a rebuild does not re-read
  /// the file every time the list scrolls or the theme changes.
  Future<Uint8List?>? _bytes;

  @override
  void initState() {
    super.initState();
    final FileSource? source = widget.file.source;

    if (source is AndroidUriSource) {
      // Still and moving alike: the provider makes both, and neither costs
      // more than the preview itself.
      if (widget.file.kind == FileKind.image ||
          widget.file.kind == FileKind.video) {
        _bytes = AndroidFiles.thumbnail(
          source.uri,
          FileThumbnail.providerPreviewPixels,
        );
      }
      return;
    }

    if (!_isPreviewable || source == null || source.path != null) return;
    _bytes = source.readAsBytes();
  }

  bool get _isPreviewable =>
      widget.file.kind == FileKind.image &&
      widget.file.size <= FileThumbnail.maxPreviewBytes;

  IconData get _icon => switch (widget.file.kind) {
        FileKind.image => Icons.image_outlined,
        FileKind.video => Icons.movie_outlined,
        FileKind.audio => Icons.audiotrack_rounded,
        FileKind.document => Icons.description_outlined,
        FileKind.archive => Icons.folder_zip_outlined,
        FileKind.other => Icons.insert_drive_file_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final double size = widget.size;

    final Widget fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.primarySoft,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Icon(_icon, size: 20, color: c.primary),
    );

    if (!_isPreviewable && _bytes == null) return fallback;

    final int cacheWidth =
        (size * MediaQuery.devicePixelRatioOf(context)).round();
    final String? path = widget.file.source?.path;

    final Widget image;
    if (path != null && _isPreviewable) {
      image = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.low,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stack) => fallback,
      );
    } else if (_bytes != null) {
      image = FutureBuilder<Uint8List?>(
        future: _bytes,
        builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
          final Uint8List? data = snapshot.data;
          if (data == null) return fallback;
          return Image.memory(
            data,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.low,
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stack) =>
                    fallback,
          );
        },
      );
    } else {
      return fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.sm),
      child: image,
    );
  }
}
