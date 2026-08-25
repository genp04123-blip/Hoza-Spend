import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/log.dart';

/// Opens the folder a received file was saved into.
///
/// Windows only, and deliberately with no package behind it: `explorer.exe`
/// takes a directory path directly. Opening a *file* would need a handler
/// lookup on desktop and an intent on Android, which is a plugin and a
/// permissions story for something the guide never asked for.
class RevealService {
  const RevealService._();

  static const String _tag = 'Storage';

  static bool get isSupported => Platform.isWindows;

  /// Shows the folder containing [filePath]. Silent if unsupported.
  static Future<void> openContainingFolder(String filePath) async {
    if (!isSupported) return;
    try {
      // The folder rather than "/select,<file>": Dart quotes arguments on
      // Windows, and explorer rejects a quoted /select for any path with a
      // space in it.
      await Process.run('explorer.exe', <String>[p.dirname(filePath)]);
    } catch (error) {
      Log.warn(_tag, 'Could not open folder: $error');
    }
  }
}
