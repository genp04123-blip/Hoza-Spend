import '../models/transfer.dart';

/// Human-readable formatting for the numbers HozaSend shows constantly. Kept
/// pure and dependency-free so it is trivial to reason about.
class Formatters {
  const Formatters._();

  static const List<String> _units = <String>['B', 'KB', 'MB', 'GB', 'TB'];

  /// 23500000 renders as "22.4 MB". One decimal below 100 and none above, so
  /// the number stops jittering in width while a transfer runs.
  static String bytes(int value) {
    if (value < 1024) return '$value B';
    double size = value.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < _units.length - 1) {
      size /= 1024;
      unit++;
    }
    final String text =
        size >= 100 ? size.round().toString() : size.toStringAsFixed(1);
    return '$text ${_units[unit]}';
  }

  /// Bytes per second rendered as "12.6 MB/s".
  static String speed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '--';
    return '${bytes(bytesPerSecond.round())}/s';
  }

  /// Short, friendly countdown. Null renders as a dash rather than a guess.
  static String eta(Duration? value) {
    if (value == null) return '--';
    final int total = value.inSeconds;
    if (total <= 1) return 'almost done';
    if (total < 60) return '~$total seconds remaining';
    final int minutes = total ~/ 60;
    if (minutes < 60) {
      return minutes == 1
          ? '~1 minute remaining'
          : '~$minutes minutes remaining';
    }
    final int hours = minutes ~/ 60;
    final int rest = minutes % 60;
    return rest == 0 ? '~$hours h remaining' : '~$hours h $rest m remaining';
  }

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// History timestamps: "14:32", "Yesterday 09:04", "12 Mar 2026".
  static String timestamp(DateTime value, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final DateTime day = DateTime(value.year, value.month, value.day);
    final DateTime today =
        DateTime(reference.year, reference.month, reference.day);
    final int diff = today.difference(day).inDays;
    final String time = '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return time;
    if (diff == 1) return 'Yesterday $time';
    return '${value.day} ${_months[value.month - 1]} ${value.year}';
  }

  /// Extension to broad kind.
  ///
  /// Only ever decides an icon and whether a thumbnail is worth attempting -
  /// nothing here can stop a file being sent, and a kind that is missing
  /// simply gets the generic icon. It is long anyway, because the icon is the
  /// one thing that tells a user at a glance that the right file is queued,
  /// and a folder of spreadsheets all showing "unknown file" says the app does
  /// not really handle them even when it does.
  static const Map<String, FileKind> _kindByExtension = <String, FileKind>{
    // Images
    'jpg': FileKind.image, 'jpeg': FileKind.image, 'jfif': FileKind.image,
    'png': FileKind.image, 'gif': FileKind.image, 'webp': FileKind.image,
    'bmp': FileKind.image, 'heic': FileKind.image, 'heif': FileKind.image,
    'avif': FileKind.image, 'svg': FileKind.image, 'ico': FileKind.image,
    'tif': FileKind.image, 'tiff': FileKind.image, 'jxl': FileKind.image,
    'jp2': FileKind.image, 'psd': FileKind.image, 'ai': FileKind.image,
    'eps': FileKind.image, 'dng': FileKind.image, 'raw': FileKind.image,
    'cr2': FileKind.image, 'nef': FileKind.image, 'arw': FileKind.image,
    'orf': FileKind.image, 'rw2': FileKind.image,
    // Video
    'mp4': FileKind.video, 'mov': FileKind.video, 'mkv': FileKind.video,
    'avi': FileKind.video, 'webm': FileKind.video, 'm4v': FileKind.video,
    '3gp': FileKind.video, 'flv': FileKind.video, 'wmv': FileKind.video,
    'mpg': FileKind.video, 'mpeg': FileKind.video, 'ts': FileKind.video,
    'mts': FileKind.video, 'm2ts': FileKind.video, 'ogv': FileKind.video,
    // Audio
    'mp3': FileKind.audio, 'wav': FileKind.audio, 'flac': FileKind.audio,
    'aac': FileKind.audio, 'ogg': FileKind.audio, 'oga': FileKind.audio,
    'opus': FileKind.audio, 'm4a': FileKind.audio, 'wma': FileKind.audio,
    'amr': FileKind.audio, 'mid': FileKind.audio, 'midi': FileKind.audio,
    'aiff': FileKind.audio, 'alac': FileKind.audio, 'ape': FileKind.audio,
    // Documents, and everything that is really text
    'pdf': FileKind.document, 'doc': FileKind.document,
    'docx': FileKind.document, 'xls': FileKind.document,
    'xlsx': FileKind.document, 'ppt': FileKind.document,
    'pptx': FileKind.document, 'txt': FileKind.document,
    'md': FileKind.document, 'rtf': FileKind.document,
    'csv': FileKind.document, 'tsv': FileKind.document,
    'odt': FileKind.document, 'ods': FileKind.document,
    'odp': FileKind.document, 'epub': FileKind.document,
    'mobi': FileKind.document, 'azw3': FileKind.document,
    'djvu': FileKind.document, 'pages': FileKind.document,
    'numbers': FileKind.document, 'key': FileKind.document,
    'tex': FileKind.document, 'log': FileKind.document,
    'json': FileKind.document, 'xml': FileKind.document,
    'yaml': FileKind.document, 'yml': FileKind.document,
    'html': FileKind.document, 'htm': FileKind.document,
    'ipynb': FileKind.document, 'srt': FileKind.document,
    'vcf': FileKind.document, 'ics': FileKind.document,
    // Archives, packages and installers. One icon between them on purpose:
    // what they have in common, to a person looking at a list, is that they
    // are a bundle of something rather than a thing to read.
    'zip': FileKind.archive, 'rar': FileKind.archive, '7z': FileKind.archive,
    'tar': FileKind.archive, 'gz': FileKind.archive, 'tgz': FileKind.archive,
    'bz2': FileKind.archive, 'xz': FileKind.archive, 'zst': FileKind.archive,
    'cab': FileKind.archive, 'iso': FileKind.archive, 'jar': FileKind.archive,
    'apk': FileKind.archive, 'apks': FileKind.archive,
    'aab': FileKind.archive, 'ipa': FileKind.archive,
    'exe': FileKind.archive, 'msi': FileKind.archive,
    'msix': FileKind.archive, 'appx': FileKind.archive,
    'dmg': FileKind.archive, 'pkg': FileKind.archive,
    'deb': FileKind.archive, 'rpm': FileKind.archive,
    'appimage': FileKind.archive, 'snap': FileKind.archive,
    'flatpak': FileKind.archive, 'cbz': FileKind.archive,
  };

  /// The kind of file [fileName] looks like.
  ///
  /// A name with no extension, or one nothing recognises, is [FileKind.other]
  /// - which is a perfectly ordinary answer and never a reason to refuse a
  /// file. A leading dot is not an extension: `.gitignore` is a file called
  /// `.gitignore`, not a `gitignore` file.
  static FileKind kindOf(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return FileKind.other;
    return _kindByExtension[fileName.substring(dot + 1).toLowerCase()] ??
        FileKind.other;
  }
}
