import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/log.dart';

/// Resolves where received files are written.
///
/// Only the default location is decided here; creating directories and moving
/// completed files happens in the storage work of Section 7.
class StorageService {
  const StorageService._();

  static const String folderName = 'HozaSend';

  static const String _tag = 'Storage';

  /// The default download directory for this platform.
  ///
  /// Windows: a HozaSend folder inside the user's Downloads.
  /// Android: the app's own external files directory, which is always writable
  /// with no permission prompt. Writing into the public Downloads folder needs
  /// MediaStore under scoped storage, which is platform code - that lands in
  /// the Android polish of Section 8.
  static Future<String> defaultDownloadDirectory() async {
    if (Platform.isAndroid) {
      try {
        // Staging, not the final home. Scoped storage means a file cannot be
        // streamed straight into public Downloads, so it is written and
        // verified here and then handed to MediaStore by DownloadsPublisher.
        final Directory? external = await getExternalStorageDirectory();
        if (external != null) return p.join(external.path, folderName);
      } catch (_) {
        // Fall through to documents.
      }
    } else if (!Platform.isIOS) {
      // iOS is skipped deliberately: it has no shared Downloads folder at all,
      // and getDownloadsDirectory would either throw or point somewhere the
      // user cannot reach. Its files go to Documents, which UIFileSharingEnabled
      // surfaces in the Files app under "On My iPhone".
      try {
        final Directory? downloads = await getDownloadsDirectory();
        if (downloads != null) return p.join(downloads.path, folderName);
      } catch (_) {
        // getDownloadsDirectory is unsupported on some platforms.
      }
    }
    final Directory documents = await getApplicationDocumentsDirectory();
    return p.join(documents.path, folderName);
  }

  /// Where to tell the user their files went.
  ///
  /// On Android that is not [defaultDownloadDirectory]: files pass through it
  /// and end up in the phone's own Downloads folder, and showing the staging
  /// path would send someone looking in the wrong place.
  static String userFacingLocation(String? path) {
    if (Platform.isAndroid) return 'Downloads/$folderName';
    // What the Files app calls it, not the container path underneath, which
    // means nothing to anyone looking for their file.
    if (Platform.isIOS) return 'On My iPhone / $folderName';
    return path == null || path.isEmpty ? 'Resolving...' : path;
  }

  /// The phone's public Downloads folder. Android exposes no API for it that
  /// works under scoped storage, and this path has been stable for a decade.
  static const String _androidDownloads = '/storage/emulated/0/Download';

  /// Creates the HozaSend folder up front, so the user can see where files
  /// will land before the first transfer arrives.
  ///
  /// Returns false on Android 10 and later, and that is expected rather than a
  /// failure: scoped storage does not let an app create an empty folder in
  /// public Downloads. MediaStore makes it when the first file is published,
  /// so the folder appears with its first file instead of before it.
  static Future<bool> createDownloadFolder() async {
    try {
      final Directory directory = Platform.isAndroid
          ? Directory(p.join(_androidDownloads, folderName))
          : Directory(await defaultDownloadDirectory());

      if (await directory.exists()) return true;
      await directory.create(recursive: true);
      return directory.existsSync();
    } catch (error) {
      Log.info(_tag, 'Could not pre-create the download folder: $error');
      return false;
    }
  }

  /// Creates the download directory if it is not there yet.
  static Future<Directory> ensureDirectory(String path) async {
    final Directory directory = Directory(path);
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  /// What a file is called when nothing usable survived sanitising.
  static const String fallbackName = 'received_file';

  /// Windows caps a path component at 255. The rest is room for the " (12)"
  /// a duplicate gets and the `.hozapart` a partial file wears.
  static const int _maxNameLength = 240;

  /// Beyond this, an "extension" is not one - it is the tail of a name that
  /// happens to contain a dot, and keeping it would waste the whole budget.
  static const int _maxExtensionLength = 24;

  /// How deep a folder a sender may recreate here.
  ///
  /// Real folders are a handful of levels; anything past this is either a
  /// mistake or an attempt to push a path past what the filesystem will take.
  static const int _maxDepth = 16;

  /// Names Windows refuses, in any directory, with or without an extension.
  ///
  /// `con.txt` is a perfectly ordinary file on a Mac or a phone and cannot be
  /// created on Windows at all. Renaming it is the only way the transfer
  /// succeeds; the alternative is a file that always fails to arrive.
  static const Set<String> _reservedNames = <String>{
    'con', 'prn', 'aux', 'nul',
    'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
    'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
  };

  /// Strips everything from a received filename except the name itself.
  ///
  /// This is a security boundary, not tidiness. The name arrives from another
  /// device, and a peer that sent `../../../autorun.inf` would otherwise get a
  /// write outside the download folder. Separators, drive letters, traversal
  /// segments and control characters all go.
  ///
  /// What does *not* go is anything the user would notice losing. A leading
  /// dot is kept, so `.gitignore` and `.env` arrive under their own names
  /// rather than as `gitignore` and `env`. The extension is kept when a very
  /// long name has to be shortened, because a `.docx` that arrives with no
  /// extension is a file the receiving device no longer knows how to open.
  static String safeFileName(String name) {
    // Take the last segment under either separator, so neither a Windows nor a
    // POSIX path survives.
    String cleaned = name.split(RegExp(r'[\\/]')).last;
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x1F<>:"|?*]'), '_');
    // Windows silently drops trailing dots and spaces from a name, which would
    // leave the file on disk called something other than what was checked for
    // collisions. Dropping them here keeps the two in agreement - and it is
    // also what turns `.` and `..` into nothing at all.
    cleaned = _trimEdges(cleaned);
    if (cleaned.isEmpty) return fallbackName;

    // Windows matches a reserved device name on the part before the first dot,
    // so `con`, `con.txt` and `con.tar.gz` are all refused.
    if (_reservedNames.contains(cleaned.split('.').first.toLowerCase())) {
      cleaned = '_$cleaned';
    }

    if (cleaned.length <= _maxNameLength) return cleaned;

    final String extension = p.extension(cleaned);
    final String keep =
        extension.length <= _maxExtensionLength ? extension : '';
    final String stem =
        _trimEdges(cleaned.substring(0, _maxNameLength - keep.length));
    return stem.isEmpty ? fallbackName : '$stem$keep';
  }

  /// Trailing dots and spaces, and a name that is nothing else.
  static String _trimEdges(String value) =>
      value.replaceAll(RegExp(r'[ .]+$'), '').trim();

  /// The folder part of a relative path from another device, sanitised.
  ///
  /// [relativePath] is the whole path the sender used, file name included -
  /// `photos/2026/trip.jpg` - and what comes back is `photos/2026`, ready to
  /// be joined onto the download folder. The file's own name is applied
  /// separately by [uniquePath], which is what makes a duplicate inside a
  /// received folder behave like a duplicate anywhere else.
  ///
  /// Every segment goes through [safeFileName], and `.` and `..` are dropped
  /// outright, so no path from a peer can name anything above the download
  /// folder however it is spelled. Empty when there is no folder to rebuild.
  static String safeSubDirectory(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) return '';

    final List<String> raw = relativePath.split(RegExp(r'[\\/]'));
    // The last segment is the file itself.
    final List<String> folders = raw.sublist(0, raw.length - 1);

    final List<String> segments = <String>[];
    for (final String segment in folders) {
      if (segment.isEmpty || segment == '.' || segment == '..') continue;
      final String safe = safeFileName(segment);
      if (safe.isEmpty) continue;
      segments.add(safe);
      if (segments.length == _maxDepth) break;
    }
    return segments.join(p.separator);
  }

  /// A path inside [directory] that nothing occupies yet.
  ///
  /// Receiving `report.pdf` twice gives `report.pdf` and `report (1).pdf`
  /// rather than silently destroying the first one.
  static Future<String> uniquePath(Directory directory, String name) async {
    final String safe = safeFileName(name);
    // Split the way the name reads rather than the way `package:path` does:
    // for `.gitignore` there is no extension, and treating the whole name as
    // one would produce ` (1).gitignore` for the second copy.
    final String extension = p.extension(safe);
    final String stem = extension.isEmpty
        ? safe
        : safe.substring(0, safe.length - extension.length);

    String candidate = p.join(directory.path, safe);
    int counter = 1;
    while (await File(candidate).exists() ||
        await File('$candidate${AppConstants.partialSuffix}').exists()) {
      candidate = p.join(directory.path, '$stem ($counter)$extension');
      counter++;
    }
    return candidate;
  }

  /// Shortens a path for display so a deep Windows path does not blow out the
  /// settings row: "...\\Downloads\\HozaSend".
  static String displayPath(String? path, {int segments = 2}) {
    if (path == null || path.isEmpty) return 'Not set';
    final List<String> parts =
        p.split(path).where((String s) => s.isNotEmpty).toList();
    if (parts.length <= segments) return path;
    return '...${p.separator}${parts.sublist(parts.length - segments).join(p.separator)}';
  }
}
