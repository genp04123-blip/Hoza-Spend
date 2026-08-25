import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../utils/log.dart';

/// Where a published file ended up, in the two senses a file has on Android.
///
/// [location] is for the user to read; [uri] is the only thing that can
/// actually reopen the file. Under scoped storage those are not the same
/// string, and treating them as one is what leaves a received file visible in
/// Downloads but impossible to open from inside the app.
class PublishedFile {
  const PublishedFile({required this.location, this.uri});

  /// `Download/HozaSend/name.jpg` on Android 10 and up, where MediaStore never
  /// hands back a path. A real path below that.
  final String location;

  /// The MediaStore entry, when there is one.
  final String? uri;
}

/// Moves a received file into the phone's public Downloads folder.
///
/// Android only, and only because it has to be. Under scoped storage an app
/// cannot write into Downloads by path: MediaStore hands back a stream, not a
/// location. So a transfer is streamed and verified into the app's own folder
/// first, and this publishes the finished file afterwards.
///
/// Desktop needs none of this - it writes straight into Downloads/HozaSend.
class DownloadsPublisher {
  const DownloadsPublisher._();

  static const MethodChannel _channel = MethodChannel('hozasend/storage');
  static const String _tag = 'Storage';

  static bool get isSupported => Platform.isAndroid;

  /// Returns where the file ended up, or null if it could not be published -
  /// in which case the caller keeps the copy it already has rather than losing
  /// the transfer over a filing problem.
  static Future<PublishedFile?> publish(String path) async {
    if (!isSupported) return null;
    final String name = p.basename(path);
    try {
      final Map<Object?, Object?>? published =
          await _channel.invokeMethod<Map<Object?, Object?>>(
        'publishToDownloads',
        <String, Object?>{
          'path': path,
          'name': name,
          'mimeType': mimeTypeOf(name),
        },
      );
      if (published == null) {
        Log.warn(_tag, 'Could not publish $name to Downloads');
        return null;
      }
      final String? location = published['location'] as String?;
      if (location == null) return null;
      return PublishedFile(
        location: location,
        uri: published['uri'] as String?,
      );
    } on PlatformException catch (error) {
      Log.warn(_tag, 'Publish failed: ${error.message}');
      return null;
    } on MissingPluginException {
      // An older host build without the handler.
      return null;
    }
  }

  static const Map<String, String> _types = <String, String>{
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
    'gif': 'image/gif', 'webp': 'image/webp', 'heic': 'image/heic',
    'bmp': 'image/bmp', 'svg': 'image/svg+xml',
    'mp4': 'video/mp4', 'mkv': 'video/x-matroska', 'mov': 'video/quicktime',
    'avi': 'video/x-msvideo', 'webm': 'video/webm', 'm4v': 'video/x-m4v',
    'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'flac': 'audio/flac',
    'aac': 'audio/aac', 'ogg': 'audio/ogg', 'm4a': 'audio/mp4',
    'pdf': 'application/pdf', 'txt': 'text/plain', 'md': 'text/markdown',
    'zip': 'application/zip', 'rar': 'application/vnd.rar',
    '7z': 'application/x-7z-compressed', 'gz': 'application/gzip',
    'tar': 'application/x-tar',
    'apk': 'application/vnd.android.package-archive',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx':
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  };

  /// A best guess from the extension. Worth getting roughly right: it is what
  /// decides whether tapping the file in a file manager offers to open it in
  /// something sensible.
  static String mimeTypeOf(String fileName) {
    final String extension =
        p.extension(fileName).replaceFirst('.', '').toLowerCase();
    return _types[extension] ?? 'application/octet-stream';
  }
}
