import 'dart:io';

import 'package:flutter/services.dart';

import '../models/transfer.dart';
import '../utils/log.dart';
import 'downloads_publisher.dart';

/// Hands a received file to whatever the device already opens that kind with.
///
/// Every kind, not a list of them: a photo goes to the gallery, a PDF to the
/// PDF reader, a song to the music player, a spreadsheet to whatever is
/// installed - because the mime type is passed along and the choice belongs to
/// the OS, not to HozaSend. A file this device has nothing for reports back as
/// unopenable rather than failing silently, which is the one case worth a word
/// to the user.
///
/// Deliberately with no package behind it. Android needs an intent, which the
/// app already has a method channel for; the desktops each take one command.
class OpenService {
  const OpenService._();

  /// The same channel the Downloads publisher uses: both are the one native
  /// conversation about where a received file lives.
  static const MethodChannel _channel = MethodChannel('hozasend/storage');

  static const String _tag = 'Storage';

  static bool get isSupported =>
      Platform.isAndroid ||
      Platform.isWindows ||
      Platform.isMacOS ||
      Platform.isLinux;

  /// Whether [file] is something this device can hand to another app.
  ///
  /// False for a sent file, for a transfer that never finished, and for a
  /// history entry written before the app started keeping the handle.
  static bool canOpen(TransferFile file) => _target(file) != null;

  /// Opens [file] in its default app. Returns false if it could not be opened
  /// - nothing installed handles it, or the file has since been moved or
  /// deleted from outside the app.
  static Future<bool> open(TransferFile file) async {
    final String? target = _target(file);
    if (target == null) return false;
    if (Platform.isAndroid) return _openOnAndroid(target, file.name);
    return _openOnDesktop(target);
  }

  /// What to hand the OS, or null if there is nothing openable.
  static String? _target(TransferFile file) {
    if (!isSupported) return null;
    if (file.openUri case final String uri when uri.isNotEmpty) return uri;

    final String? path = file.savedPath;
    if (path == null || path.isEmpty) return null;

    // On Android a published file's location is a line of text for the user -
    // `Download/HozaSend/name.jpg` - and not a path anything can open. Only an
    // absolute path is a real handle, which is what pre-scoped-storage phones
    // and the desktops still give.
    if (Platform.isAndroid && !path.startsWith('/')) return null;
    return path;
  }

  static Future<bool> _openOnAndroid(String target, String name) async {
    try {
      final bool? opened = await _channel.invokeMethod<bool>(
        'openFile',
        <String, Object?>{
          'target': target,
          // Passed so the intent can say what it is offering. Without a type
          // Android has nothing to match against and the chooser comes up
          // empty even when the right app is installed.
          'mimeType': DownloadsPublisher.mimeTypeOf(name),
        },
      );
      return opened ?? false;
    } on PlatformException catch (error) {
      Log.warn(_tag, 'Could not open $name: ${error.message}');
      return false;
    } on MissingPluginException {
      // An older host build without the handler.
      return false;
    }
  }

  /// One command each, and each one is the platform's own "open this the way
  /// the user would have".
  static Future<bool> _openOnDesktop(String path) async {
    try {
      if (!await File(path).exists()) return false;

      final ProcessResult result;
      if (Platform.isWindows) {
        // The empty argument is `start`'s window title. Without it, a quoted
        // path is taken as the title and nothing opens.
        result = await Process.run('cmd', <String>['/c', 'start', '', path]);
      } else if (Platform.isMacOS) {
        result = await Process.run('open', <String>[path]);
      } else {
        result = await Process.run('xdg-open', <String>[path]);
      }
      return result.exitCode == 0;
    } catch (error) {
      Log.warn(_tag, 'Could not open file: $error');
      return false;
    }
  }
}
