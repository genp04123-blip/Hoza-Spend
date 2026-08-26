import 'dart:io';

import 'package:flutter/services.dart';

import '../models/transfer.dart';
import '../utils/log.dart';

/// Removes a received file from the device, so a history row can take the file
/// with it when it goes.
///
/// Only ever a file this app wrote itself: on the desktops that is a path under
/// Downloads/HozaSend, and on Android it is either a path (pre-scoped storage)
/// or the MediaStore row the file was published as. A row the app created is a
/// row it may delete without asking the system for anything more.
class DeleteService {
  const DeleteService._();

  /// The same channel the Downloads publisher and OpenService use: one native
  /// conversation about where a received file lives.
  static const MethodChannel _channel = MethodChannel('hozasend/storage');

  static const String _tag = 'Storage';

  static bool get isSupported =>
      Platform.isAndroid ||
      Platform.isWindows ||
      Platform.isMacOS ||
      Platform.isLinux;

  /// Whether [file] is something on this device that can be deleted.
  ///
  /// False for a sent file (it lives on the other device), for a transfer that
  /// never finished, and for a history entry written before the app started
  /// keeping the handle.
  static bool canDelete(TransferFile file) => _target(file) != null;

  /// Deletes [file]. Returns true when the file is gone afterwards - including
  /// when it had already been removed from outside the app, because the point
  /// is the end state, not the act.
  static Future<bool> delete(TransferFile file) async {
    final String? target = _target(file);
    if (target == null) return false;
    if (Platform.isAndroid) return _deleteOnAndroid(target, file.name);
    return _deleteOnDesktop(target, file.name);
  }

  /// What to hand the OS, or null if there is nothing to delete.
  static String? _target(TransferFile file) {
    if (!isSupported) return null;
    if (file.openUri case final String uri when uri.isNotEmpty) return uri;

    final String? path = file.savedPath;
    if (path == null || path.isEmpty) return null;

    // On Android a published file's location is a line of text for the user -
    // `Download/HozaSend/name.jpg` - and not a path anything can act on. Only
    // an absolute path is a real handle.
    if (Platform.isAndroid && !path.startsWith('/')) return null;
    return path;
  }

  static Future<bool> _deleteOnAndroid(String target, String name) async {
    try {
      final bool? deleted = await _channel.invokeMethod<bool>(
        'deleteFile',
        <String, Object?>{'target': target},
      );
      return deleted ?? false;
    } on PlatformException catch (error) {
      Log.warn(_tag, 'Could not delete $name: ${error.message}');
      return false;
    } on MissingPluginException {
      // An older host build without the handler.
      return false;
    }
  }

  static Future<bool> _deleteOnDesktop(String path, String name) async {
    try {
      final File file = File(path);
      if (!await file.exists()) return true;
      await file.delete();
      return true;
    } catch (error) {
      Log.warn(_tag, 'Could not delete $name: $error');
      return false;
    }
  }
}
