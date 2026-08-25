import 'package:flutter/foundation.dart';

/// Tagged developer logging.
///
/// Two rules the guide is firm about: never log file contents or anything else
/// personal, and never log per chunk during a transfer. Debug builds only, so
/// a release build carries no logging cost at all.
class Log {
  const Log._();

  static void info(String tag, String message) => _write(tag, message);

  static void warn(String tag, String message) => _write('$tag!', message);

  static void error(String tag, String message, [Object? error]) =>
      _write('$tag!!', error == null ? message : '$message ($error)');

  static void _write(String tag, String message) {
    if (!kDebugMode) return;
    debugPrint('[$tag] $message');
  }
}
