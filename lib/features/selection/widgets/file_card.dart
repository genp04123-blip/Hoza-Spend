import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/file_source.dart';
import '../../../core/models/transfer.dart';
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
                  file.name,
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

/// A real preview for images, otherwise a tinted kind icon.
///
/// Two routes, because the two platforms hand back different things. Desktop
/// gives a path, so `Image.file` decodes straight from disk at thumbnail size.
/// Android gives a storage-access URI with no path, so the bytes have to be
/// read through the picker - which is only acceptable because it is capped at
/// [maxPreviewBytes] and the result is decoded down immediately.
///
/// Video thumbnails would need a decoder plugin on both platforms; the kind
/// icon is the honest alternative for now.
class FileThumbnail extends StatefulWidget {
  const FileThumbnail({super.key, required this.file, this.size = 46});

  /// Images larger than this get an icon instead. A preview is never worth
  /// pulling many megabytes into memory for.
  static const int maxPreviewBytes = 6 * 1024 * 1024;

  final TransferFile file;
  final double size;

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  /// Held in state rather than built in `build`, so a rebuild does not re-read
  /// the file every time the list scrolls or the theme changes.
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    final FileSource? source = widget.file.source;
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

    if (!_isPreviewable) return fallback;

    final int cacheWidth =
        (size * MediaQuery.devicePixelRatioOf(context)).round();
    final String? path = widget.file.source?.path;

    final Widget image;
    if (path != null) {
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
      image = FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
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
