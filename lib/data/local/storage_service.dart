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

  /// Strips everything from a received filename except the name itself.
  ///
  /// This is a security boundary, not tidiness. The name arrives from another
  /// device, and a peer that sent `../../../autorun.inf` would otherwise get a
  /// write outside the download folder. Separators, drive letters, traversal
  /// segments and control characters all go.
  static String safeFileName(String name) {
    // Take the last segment under either separator, so neither a Windows nor a
    // POSIX path survives.
    String cleaned = name.split(RegExp(r'[\\/]')).last;
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x1F<>:"|?*]'), '_');
    cleaned = cleaned.replaceAll(RegExp(r'^\.+'), '');
    cleaned = cleaned.trim();
    if (cleaned.isEmpty) return 'received_file';
    // Windows caps a path component at 255; leave room for the " (12)" suffix.
    return cleaned.length <= 240 ? cleaned : cleaned.substring(0, 240);
  }

  /// A path inside [directory] that nothing occupies yet.
  ///
  /// Receiving `report.pdf` twice gives `report.pdf` and `report (1).pdf`
  /// rather than silently destroying the first one.
  static Future<String> uniquePath(Directory directory, String name) async {
    final String safe = safeFileName(name);
    final String stem = p.basenameWithoutExtension(safe);
    final String extension = p.extension(safe);

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
