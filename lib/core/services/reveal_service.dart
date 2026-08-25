import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../utils/log.dart';

/// Opens the folder a received file was saved into.
///
/// Desktop only. Android has no equivalent - a file manager there is an intent,
/// not a folder - so it is simply unsupported.
class RevealService {
  const RevealService._();

  /// The same channel the Downloads publisher and OpenService use: one native
  /// conversation about where a received file lives.
  static const MethodChannel _channel = MethodChannel('hozasend/storage');

  static const String _tag = 'Storage';

  static bool get isSupported => Platform.isWindows || Platform.isMacOS;

  /// Shows the folder containing [filePath]. Silent if unsupported.
  static Future<void> openContainingFolder(String filePath) async {
    if (!isSupported) return;
    try {
      if (Platform.isMacOS) {
        // Through the channel rather than `open -R`: the App Sandbox blocks a
        // sandboxed process from driving LaunchServices, so the command fails
        // quietly. NSWorkspace on the other side also selects the file itself,
        // which Explorer cannot be trusted to do.
        await _channel.invokeMethod<bool>(
          'revealInFinder',
          <String, Object?>{'target': filePath},
        );
        return;
      }
      // The folder rather than "/select,<file>": Dart quotes arguments on
      // Windows, and explorer rejects a quoted /select for any path with a
      // space in it.
      await Process.run('explorer.exe', <String>[p.dirname(filePath)]);
    } on PlatformException catch (error) {
      Log.warn(_tag, 'Could not open folder: ${error.message}');
    } on MissingPluginException {
      // An older host build without the handler.
    } catch (error) {
      Log.warn(_tag, 'Could not open folder: $error');
    }
  }
}
