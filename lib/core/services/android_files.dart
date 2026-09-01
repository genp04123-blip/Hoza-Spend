import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../models/file_source.dart';
import '../utils/log.dart';

/// One file the Android picker handed back, as a handle rather than a copy.
class AndroidPickedFile {
  const AndroidPickedFile({
    required this.uri,
    required this.name,
    required this.size,
    this.modifiedAt,
    this.relativePath,
  });

  /// The `content://` document URI. Stable for the life of the grant, which is
  /// what makes it usable as an identity: picking the same file twice gives
  /// the same string both times.
  final String uri;

  final String name;
  final int size;
  final DateTime? modifiedAt;

  /// Where the file sat inside a picked folder, file name included. Null for a
  /// file chosen on its own.
  final String? relativePath;

  static AndroidPickedFile? fromMap(Map<Object?, Object?> map) {
    final Object? uri = map['uri'];
    final Object? name = map['name'];
    final Object? size = map['size'];
    // A file whose size the provider will not report cannot be offered: the
    // receiver is promised a byte count before the first byte arrives.
    if (uri is! String || uri.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (size is! int || size < 0) return null;
    return AndroidPickedFile(
      uri: uri,
      name: name,
      size: size,
      modifiedAt: switch (map['modified']) {
        final int ms when ms > 0 => DateTime.fromMillisecondsSinceEpoch(ms),
        _ => null,
      },
      relativePath: switch (map['rel']) {
        final String rel when rel.isNotEmpty => rel,
        _ => null,
      },
    );
  }
}

/// Reads a picked file on Android straight from its content URI.
///
/// This exists because of what the alternative costs. Every Flutter file picker
/// on Android answers a pick by *copying* the chosen file into the app's cache
/// and handing back the copy's path - so choosing a 4 GB video needs 4 GB of
/// free space before a single byte has been sent, takes as long as the copy
/// takes, and leaves the copy behind afterwards. For an app whose entire job is
/// moving large files that is the wrong trade twice over.
///
/// The Storage Access Framework will stream the original perfectly well. What
/// it will not do is give it a path, so reading has to go through the platform
/// - one open, then chunks pulled across on demand, then a close. Pulled rather
/// than pushed: the transfer asks for the next chunk only when it is ready for
/// it, so a slow network cannot make the reader queue a file in memory.
class AndroidUriSource extends FileSource {
  const AndroidUriSource(this.uri);

  /// Bytes fetched per platform call.
  ///
  /// Much larger than the wire chunk on purpose. The frame size is what bounds
  /// the receiver and how fast a pause bites; this is the cost of a round trip
  /// across the platform channel, and 64 KB at a time would spend more of the
  /// transfer in message dispatch than in the file. The sender re-slices what
  /// arrives here down to the frame size.
  static const int readSize = 512 * 1024;

  /// A cap for [readAsBytes], which only ever serves a thumbnail. Streaming has
  /// no such limit.
  static const int _maxWholeRead = 32 * 1024 * 1024;

  final String uri;

  @override
  String get key => uri;

  /// Deliberately null. There is no path: that is the whole point.
  @override
  String? get path => null;

  @override
  Stream<List<int>> openRead() async* {
    final String? handle = await AndroidFiles.openStream(uri);
    if (handle == null) {
      throw const FileSystemException('Could not open the selected file');
    }
    try {
      while (true) {
        final Uint8List? chunk = await AndroidFiles.readStream(handle, readSize);
        if (chunk == null || chunk.isEmpty) return;
        yield chunk;
      }
    } finally {
      // Closed on every path, including the one where the transfer was
      // cancelled and this generator is simply abandoned mid-file.
      await AndroidFiles.closeStream(handle);
    }
  }

  @override
  Future<Uint8List> readAsBytes() async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in openRead()) {
      builder.add(chunk);
      if (builder.length > _maxWholeRead) {
        throw const FileSystemException('File is too large to read at once');
      }
    }
    return builder.takeBytes();
  }
}

/// The Android half of picking and reading files, without a copy in the middle.
///
/// Everything here degrades to null rather than throwing. The caller falls back
/// to the cross-platform picker, which still works - it is only slower and
/// hungrier - so a device that refuses any of this loses performance, not the
/// ability to send a file.
class AndroidFiles {
  const AndroidFiles._();

  static const MethodChannel _channel = MethodChannel('hozasend/files');
  static const String _tag = 'Picker';

  static bool get isSupported => Platform.isAndroid;

  /// Opens the system document picker for any type, multi-select.
  ///
  /// Returns an empty list if the user cancelled, and null if this route is
  /// unavailable - which the caller reads as "use the other picker".
  static Future<List<AndroidPickedFile>?> pickFiles() =>
      _pick('pickFiles', 'file selection');

  /// Opens the system folder picker and lists what is inside it, recursively.
  static Future<List<AndroidPickedFile>?> pickFolder() =>
      _pick('pickFolder', 'folder selection');

  static Future<List<AndroidPickedFile>?> _pick(String method, String what) async {
    if (!isSupported) return null;
    try {
      final List<Object?>? picked =
          await _channel.invokeMethod<List<Object?>>(method);
      if (picked == null) return null;

      final List<AndroidPickedFile> files = <AndroidPickedFile>[];
      for (final Object? entry in picked) {
        if (entry is! Map<Object?, Object?>) continue;
        final AndroidPickedFile? file = AndroidPickedFile.fromMap(entry);
        // One unusable entry means the whole pick falls back, rather than the
        // user silently getting fewer files than they chose.
        if (file == null) {
          Log.warn(_tag, 'A picked item had no usable size; falling back');
          return null;
        }
        files.add(file);
      }
      return files;
    } on PlatformException catch (error) {
      Log.warn(_tag, 'Android $what failed: ${error.message}');
      return null;
    } on MissingPluginException {
      // An older host build without the handler.
      return null;
    }
  }

  /// Opens a read stream over [uri]. Returns the handle to read it with.
  static Future<String?> openStream(String uri) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>(
        'openStream',
        <String, Object?>{'uri': uri},
      );
    } on PlatformException catch (error) {
      Log.warn(_tag, 'Could not open the file: ${error.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// The next chunk, or null at the end of the file.
  static Future<Uint8List?> readStream(String handle, int max) {
    return _channel.invokeMethod<Uint8List>(
      'readStream',
      <String, Object?>{'handle': handle, 'max': max},
    );
  }

  /// A small preview of [uri], or null if the device has none for it.
  ///
  /// Kilobytes, made by the provider, and available for video as well as
  /// stills. The alternative - reading the file to decode it - costs the whole
  /// file per card, which on a screen holding a hundred of them is not a
  /// trade-off, just a crash.
  static Future<Uint8List?> thumbnail(String uri, int size) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<Uint8List>(
        'thumbnail',
        <String, Object?>{'uri': uri, 'size': size},
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> closeStream(String handle) async {
    try {
      await _channel.invokeMethod<void>(
        'closeStream',
        <String, Object?>{'handle': handle},
      );
    } catch (error) {
      // The stream is gone either way; the platform closes anything left over
      // when the activity does.
      Log.info(_tag, 'Could not close a file stream: $error');
    }
  }
}
