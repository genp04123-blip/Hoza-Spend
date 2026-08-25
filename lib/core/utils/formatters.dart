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

  static const Map<String, FileKind> _kindByExtension = <String, FileKind>{
    'jpg': FileKind.image, 'jpeg': FileKind.image, 'png': FileKind.image,
    'gif': FileKind.image, 'webp': FileKind.image, 'bmp': FileKind.image,
    'heic': FileKind.image, 'svg': FileKind.image,
    'mp4': FileKind.video, 'mov': FileKind.video, 'mkv': FileKind.video,
    'avi': FileKind.video, 'webm': FileKind.video, 'm4v': FileKind.video,
    'mp3': FileKind.audio, 'wav': FileKind.audio, 'flac': FileKind.audio,
    'aac': FileKind.audio, 'ogg': FileKind.audio, 'm4a': FileKind.audio,
    'pdf': FileKind.document, 'doc': FileKind.document,
    'docx': FileKind.document, 'xls': FileKind.document,
    'xlsx': FileKind.document, 'ppt': FileKind.document,
    'pptx': FileKind.document, 'txt': FileKind.document,
    'md': FileKind.document,
    'zip': FileKind.archive, 'rar': FileKind.archive, '7z': FileKind.archive,
    'tar': FileKind.archive, 'gz': FileKind.archive, 'apk': FileKind.archive,
  };

  static FileKind kindOf(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return FileKind.other;
    return _kindByExtension[fileName.substring(dot + 1).toLowerCase()] ??
        FileKind.other;
  }
}
