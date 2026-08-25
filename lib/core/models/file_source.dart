import 'dart:io';
import 'dart:typed_data';

/// Where a file's bytes come from.
///
/// A filesystem path is not a universal handle. Android's picker hands back a
/// storage-access URI, so anything that reads a selected file has to go through
/// this rather than assuming `File(path)` will work.
///
/// Every implementation must be able to stream. Nothing in HozaSend reads a
/// whole file into memory in order to send it.
abstract class FileSource {
  const FileSource();

  /// Stable identity, used to notice the same file being picked twice.
  String get key;

  /// A real filesystem path, where one genuinely exists. Null for an Android
  /// selection, which is exactly why [openRead] exists.
  String? get path => null;

  /// The bytes, in chunks. This is how files are sent.
  Stream<List<int>> openRead();

  /// The whole contents at once.
  ///
  /// Only for bounded uses such as building a thumbnail, and only after
  /// checking the size. Never for a transfer.
  Future<Uint8List> readAsBytes();
}

/// A file the app can reach directly on disk: desktop selections, and every
/// file this device has received.
class PathFileSource extends FileSource {
  const PathFileSource(this._path);

  final String _path;

  @override
  String get key => _path;

  @override
  String? get path => _path;

  @override
  Stream<List<int>> openRead() => File(_path).openRead();

  @override
  Future<Uint8List> readAsBytes() => File(_path).readAsBytes();
}
