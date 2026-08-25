import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../models/file_source.dart';
import '../models/transfer.dart';
import '../utils/formatters.dart';
import '../utils/ids.dart';
import '../utils/log.dart';

/// A file the picker returned. On desktop this wraps a real path; on Android it
/// wraps a storage-access URI, which is why reading goes through the picker's
/// own stream rather than `dart:io`.
class PickedFileSource extends FileSource {
  const PickedFileSource(this._file);

  final PlatformFile _file;

  @override
  String get key => _file.uri.toString();

  @override
  String? get path => _file.path;

  @override
  Stream<List<int>> openRead() => _file.readAsByteStream();

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}

/// Wraps the native file pickers and hands back [TransferFile]s.
///
/// The rule that matters: nothing here asks the picker for file contents. It
/// asks for handles. A 5 GB video has to reach the socket as a stream, and
/// pulling its bytes at selection time would defeat that before the transfer
/// layer ever saw it.
class FilePickerService {
  const FilePickerService._();

  static const String _tag = 'Picker';

  /// Android's directory picker returns a storage-access URI that cannot be
  /// listed with `dart:io`, so folder picking is offered on desktop only. The
  /// guide asks for folders "where supported"; this is honestly where.
  static bool get supportsFolders =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Opens the native picker. Returns empty if the user cancelled.
  static Future<List<TransferFile>> pickFiles() async {
    try {
      final List<PlatformFile> picked =
          await FilePicker.pickFiles(type: FileType.any);

      final List<TransferFile> files = <TransferFile>[];
      for (final PlatformFile file in picked) {
        files.add(
          TransferFile(
            id: Ids.next('f'),
            name: file.name,
            size: await file.length(),
            kind: Formatters.kindOf(file.name),
            source: PickedFileSource(file),
          ),
        );
      }
      Log.info(_tag, 'Selected ${files.length} file(s)');
      return files;
    } catch (error) {
      Log.error(_tag, 'File selection failed', error);
      return const <TransferFile>[];
    }
  }

  /// Asks for a folder, without listing it. Used to change where received
  /// files are saved.
  static Future<String?> pickDirectory() async {
    if (!supportsFolders) return null;
    try {
      return await FilePicker.getDirectoryPath();
    } catch (error) {
      Log.error(_tag, 'Folder selection failed', error);
      return null;
    }
  }

  /// Desktop only. Lists a folder recursively, skipping hidden entries and
  /// anything unreadable rather than failing the whole selection.
  static Future<List<TransferFile>> pickFolder() async {
    if (!supportsFolders) return const <TransferFile>[];
    try {
      final String? directory = await FilePicker.getDirectoryPath();
      if (directory == null) return const <TransferFile>[];
      final List<TransferFile> files = await _listDirectory(Directory(directory));
      Log.info(_tag, 'Selected folder with ${files.length} file(s)');
      return files;
    } catch (error) {
      Log.error(_tag, 'Folder selection failed', error);
      return const <TransferFile>[];
    }
  }

  /// Builds selections from paths that did not come from a picker: files
  /// dragged onto the window. A dropped directory is expanded, so dropping a
  /// folder behaves the same as choosing one.
  static Future<List<TransferFile>> fromPaths(List<String> paths) async {
    final List<TransferFile> files = <TransferFile>[];
    for (final String path in paths) {
      try {
        if (await Directory(path).exists()) {
          files.addAll(await _listDirectory(Directory(path)));
          continue;
        }
        final File file = File(path);
        if (!await file.exists()) continue;
        files.add(_fromPath(path, await file.length()));
      } catch (error) {
        // One bad path must not lose the rest of the drop.
        Log.warn(_tag, 'Skipped a dropped item: $error');
      }
    }
    Log.info(_tag, 'Dropped ${files.length} file(s)');
    return files;
  }

  static Future<List<TransferFile>> _listDirectory(Directory directory) async {
    final List<TransferFile> files = <TransferFile>[];
    await for (final FileSystemEntity entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (p.basename(entity.path).startsWith('.')) continue;
      try {
        files.add(_fromPath(entity.path, await entity.length()));
      } catch (_) {
        // One unreadable file must not lose the rest of the folder.
      }
    }
    return files;
  }

  /// A selection backed by a real path on disk: desktop picks, folder
  /// contents, and drops.
  static TransferFile _fromPath(String path, int size) {
    final String name = p.basename(path);
    return TransferFile(
      id: Ids.next('f'),
      name: name,
      size: size,
      kind: Formatters.kindOf(name),
      source: PathFileSource(path),
    );
  }
}
