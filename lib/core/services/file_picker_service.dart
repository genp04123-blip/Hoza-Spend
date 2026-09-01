import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../models/file_source.dart';
import '../models/transfer.dart';
import '../utils/formatters.dart';
import '../utils/ids.dart';
import '../utils/log.dart';
import 'android_files.dart';

/// A file the cross-platform picker returned.
///
/// On the desktops this wraps a real path and reads straight from disk. On the
/// phones the picker has already copied the file into the app's own storage
/// before handing it over, so this reads that copy - which is why Android
/// prefers [AndroidUriSource] and only falls back to here.
class PickedFileSource extends FileSource {
  const PickedFileSource(this._file, this._key);

  final PlatformFile _file;
  final String _key;

  /// What decides whether two picks are the same file.
  ///
  /// Not the picker's own URI. On the phones that URI points at a copy in a
  /// folder named after the moment it was made, so picking the same file twice
  /// produces two different strings and the same file is queued twice. The
  /// caller supplies something stable instead.
  @override
  String get key => _key;

  @override
  String? get path => _file.path;

  @override
  Stream<List<int>> openRead() => _file.readAsByteStream();

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}

/// Wraps the native file pickers and hands back [TransferFile]s.
///
/// Two rules matter here.
///
/// Nothing asks the picker for file contents; it asks for handles. A 5 GB video
/// has to reach the socket as a stream, and pulling its bytes at selection time
/// would defeat that before the transfer layer ever saw it.
///
/// And nothing filters by type. Every picker is opened for any file the OS is
/// willing to offer - documents, archives, installers, audio, video, images,
/// files with no extension at all - because the app has no business having an
/// opinion about what its user is allowed to send.
class FilePickerService {
  const FilePickerService._();

  static const String _tag = 'Picker';

  /// True where a picked path stays valid and unique for the life of the
  /// selection, which is what makes it usable as an identity.
  static bool get _hasStablePaths =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Whether this platform can offer a whole folder.
  ///
  /// The desktops walk a real directory. Android goes through the Storage
  /// Access Framework, which will list a granted tree perfectly well - it is
  /// only a path it will not give.
  ///
  /// iOS is the exception, and honestly so. Its folder picker hands back a
  /// security-scoped URL that has to be held open by the code that received it,
  /// and the plugin does not hold it - so the folder would be picked and then
  /// found empty. Offering a button that cannot work is worse than not
  /// offering it.
  static bool get supportsFolders => _hasStablePaths || Platform.isAndroid;

  /// Opens the native picker for any file type, multi-select. Returns empty if
  /// the user cancelled.
  static Future<List<TransferFile>> pickFiles() async {
    // Android first: reads the chosen files where they already are, instead of
    // copying every one of them into the cache to get a path. See
    // [AndroidUriSource].
    if (AndroidFiles.isSupported) {
      final List<AndroidPickedFile>? picked = await AndroidFiles.pickFiles();
      if (picked != null) {
        Log.info(_tag, 'Selected ${picked.length} file(s)');
        return picked.map(_fromAndroid).toList();
      }
      Log.info(_tag, 'Falling back to the cross-platform picker');
    }

    try {
      final List<PlatformFile> picked =
          await FilePicker.pickFiles(type: FileType.any);

      final List<TransferFile> files = <TransferFile>[];
      for (final PlatformFile file in picked) {
        files.add(await _fromPicked(file));
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
    if (!_hasStablePaths) return null;
    try {
      return await FilePicker.getDirectoryPath();
    } catch (error) {
      Log.error(_tag, 'Folder selection failed', error);
      return null;
    }
  }

  /// Asks for a folder and queues everything inside it.
  ///
  /// The folder's own name is kept as the first segment of each file's
  /// relative path, so what arrives on the other device is the folder, not its
  /// contents loose in the download directory.
  static Future<List<TransferFile>> pickFolder() async {
    if (!supportsFolders) return const <TransferFile>[];

    if (AndroidFiles.isSupported) {
      final List<AndroidPickedFile>? picked = await AndroidFiles.pickFolder();
      if (picked == null) return const <TransferFile>[];
      Log.info(_tag, 'Selected folder with ${picked.length} file(s)');
      return picked.map(_fromAndroid).toList();
    }

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
  /// dragged onto the window, and files another app handed over. A dropped
  /// directory is expanded, so dropping a folder behaves the same as choosing
  /// one.
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
        files.add(await _fromPath(file));
      } catch (error) {
        // One bad path must not lose the rest of the drop.
        Log.warn(_tag, 'Skipped a dropped item: $error');
      }
    }
    Log.info(_tag, 'Dropped ${files.length} file(s)');
    return files;
  }

  /// Drops the working copies the cross-platform picker leaves behind.
  ///
  /// Both phone pickers answer a selection by copying the file somewhere the
  /// app can reach and never removing it, so without this the app's storage
  /// grows by the size of everything ever sent from it. Only safe to call when
  /// nothing is queued and no transfer is running, which is why it is done at
  /// startup and nowhere else - one of those copies may be the file currently
  /// being read.
  static Future<void> clearWorkingCopies() async {
    if (_hasStablePaths) return;
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (error) {
      Log.info(_tag, 'Could not clear old working copies: $error');
    }
  }

  static Future<List<TransferFile>> _listDirectory(Directory directory) async {
    final List<TransferFile> files = <TransferFile>[];
    // Relative to the folder's *parent*, so the folder's own name survives the
    // trip and the other device rebuilds it rather than emptying it out.
    final String base = directory.parent.path;

    await for (final FileSystemEntity entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (p.basename(entity.path).startsWith('.')) continue;
      try {
        files.add(await _fromPath(entity, relativeTo: base));
      } catch (_) {
        // One unreadable file must not lose the rest of the folder.
      }
    }
    return files;
  }

  /// A selection backed by a real path on disk: desktop picks, folder
  /// contents, and drops.
  static Future<TransferFile> _fromPath(File file, {String? relativeTo}) async {
    final String path = file.path;
    final String name = p.basename(path);
    final FileStat stat = await file.stat();

    return TransferFile(
      id: Ids.next('f'),
      name: name,
      size: stat.size,
      kind: Formatters.kindOf(name),
      source: PathFileSource(path),
      modifiedAt: stat.modified,
      relativePath: relativeTo == null ? null : _relative(path, relativeTo),
    );
  }

  /// A selection from the cross-platform picker.
  static Future<TransferFile> _fromPicked(PlatformFile file) async {
    final int size = await file.length();
    final String? path = file.path;

    // Where the picker gave a real path, the file's own timestamp is right
    // there. Where it gave a copy, the copy's timestamp is the moment of the
    // copy and says nothing about the file, so nothing is claimed.
    DateTime? modified;
    if (path != null && _hasStablePaths) {
      try {
        modified = await File(path).lastModified();
      } catch (_) {
        // A file that vanished between picking and this; the send will say so.
      }
    }

    return TransferFile(
      id: Ids.next('f'),
      name: file.name,
      size: size,
      kind: Formatters.kindOf(file.name),
      source: PickedFileSource(
        file,
        _hasStablePaths && path != null ? path : '${file.name}|$size',
      ),
      modifiedAt: modified,
    );
  }

  static TransferFile _fromAndroid(AndroidPickedFile file) => TransferFile(
        id: Ids.next('f'),
        name: file.name,
        size: file.size,
        kind: Formatters.kindOf(file.name),
        source: AndroidUriSource(file.uri),
        modifiedAt: file.modifiedAt,
        relativePath: file.relativePath,
      );

  /// The path of [path] under [base], always with `/` separators so it means
  /// the same thing on the device that receives it.
  static String _relative(String path, String base) =>
      p.relative(path, from: base).replaceAll(r'\', '/');
}
