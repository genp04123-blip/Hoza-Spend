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
  ///
  /// [subPath] is the folder the file sat in on the sending device, already
  /// sanitised, so a folder sent from a laptop arrives on the phone as a
  /// folder rather than as its contents scattered through Downloads.
  /// [modifiedAt] is the age it had there.
  static Future<PublishedFile?> publish(
    String path, {
    String subPath = '',
    DateTime? modifiedAt,
  }) async {
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
          // Separators normalised: this crosses to Android, which knows only
          // one, and the path may have been built on Windows.
          'subPath': subPath.replaceAll(r'\', '/'),
          'modified': modifiedAt?.millisecondsSinceEpoch,
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

  /// Extension to mime type.
  ///
  /// Long on purpose. This one map decides which app a received file opens in:
  /// a photo reaches the gallery, an APK reaches the installer, an `.epub`
  /// reaches a reader - and anything missing from here falls back to "some
  /// file", which is how a file ends up offering a choice of nothing. It is
  /// cheaper to list an extension than to explain why a file will not open.
  static const Map<String, String> _types = <String, String>{
    // Images
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'jfif': 'image/jpeg',
    'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp',
    'heic': 'image/heic', 'heif': 'image/heif', 'avif': 'image/avif',
    'bmp': 'image/bmp', 'svg': 'image/svg+xml', 'ico': 'image/x-icon',
    'tif': 'image/tiff', 'tiff': 'image/tiff', 'raw': 'image/x-panasonic-raw',
    'dng': 'image/x-adobe-dng', 'psd': 'image/vnd.adobe.photoshop',
    // Video
    'mp4': 'video/mp4', 'mkv': 'video/x-matroska', 'mov': 'video/quicktime',
    'avi': 'video/x-msvideo', 'webm': 'video/webm', 'm4v': 'video/x-m4v',
    '3gp': 'video/3gpp', 'flv': 'video/x-flv', 'wmv': 'video/x-ms-wmv',
    'mpg': 'video/mpeg', 'mpeg': 'video/mpeg', 'ts': 'video/mp2t',
    // Audio
    'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'flac': 'audio/flac',
    'aac': 'audio/aac', 'ogg': 'audio/ogg', 'oga': 'audio/ogg',
    'opus': 'audio/opus', 'm4a': 'audio/mp4', 'wma': 'audio/x-ms-wma',
    'amr': 'audio/amr', 'mid': 'audio/midi', 'midi': 'audio/midi',
    // Documents
    'pdf': 'application/pdf', 'txt': 'text/plain', 'md': 'text/markdown',
    'rtf': 'application/rtf', 'csv': 'text/csv', 'epub': 'application/epub+zip',
    'mobi': 'application/x-mobipocket-ebook', 'djvu': 'image/vnd.djvu',
    'odt': 'application/vnd.oasis.opendocument.text',
    'ods': 'application/vnd.oasis.opendocument.spreadsheet',
    'odp': 'application/vnd.oasis.opendocument.presentation',
    // Web and data
    'html': 'text/html', 'htm': 'text/html', 'css': 'text/css',
    'json': 'application/json', 'xml': 'text/xml', 'yaml': 'text/yaml',
    'yml': 'text/yaml', 'toml': 'text/plain', 'ini': 'text/plain',
    'log': 'text/plain', 'sql': 'text/plain', 'srt': 'application/x-subrip',
    'vcf': 'text/x-vcard', 'ics': 'text/calendar',
    // Code. All text: whatever editor the device has will take them.
    'dart': 'text/plain', 'js': 'text/javascript',
    'py': 'text/x-python', 'java': 'text/x-java-source', 'kt': 'text/plain',
    'c': 'text/x-c', 'h': 'text/x-c', 'cpp': 'text/x-c', 'cs': 'text/plain',
    'go': 'text/plain', 'rs': 'text/plain', 'php': 'text/php',
    'rb': 'text/plain', 'sh': 'text/x-shellscript', 'bat': 'text/plain',
    'ps1': 'text/plain',
    // Archives
    'zip': 'application/zip', 'rar': 'application/vnd.rar',
    '7z': 'application/x-7z-compressed', 'gz': 'application/gzip',
    'bz2': 'application/x-bzip2', 'xz': 'application/x-xz',
    'tar': 'application/x-tar', 'iso': 'application/x-iso9660-image',
    // Installers and binaries
    'apk': 'application/vnd.android.package-archive',
    'exe': 'application/vnd.microsoft.portable-executable',
    'msi': 'application/x-msdownload', 'deb': 'application/vnd.debian.binary-package',
    'rpm': 'application/x-rpm', 'dmg': 'application/x-apple-diskimage',
    'jar': 'application/java-archive',
    // Fonts
    'ttf': 'font/ttf', 'otf': 'font/otf', 'woff': 'font/woff',
    'woff2': 'font/woff2', 'ttc': 'font/collection', 'eot': 'application/vnd.ms-fontobject',
    // Ebooks, notes and the rest of the long tail people actually send
    'azw3': 'application/vnd.amazon.ebook', 'fb2': 'application/x-fictionbook+xml',
    'cbz': 'application/vnd.comicbook+zip', 'cbr': 'application/vnd.comicbook-rar',
    'odg': 'application/vnd.oasis.opendocument.graphics',
    'odf': 'application/vnd.oasis.opendocument.formula',
    'rtfd': 'application/rtf', 'pages': 'application/x-iwork-pages-sffpages',
    'numbers': 'application/x-iwork-numbers-sffnumbers',
    'key': 'application/x-iwork-keynote-sffkey',
    'tex': 'text/x-tex', 'bib': 'text/x-bibtex',
    // Design and CAD
    'ai': 'application/postscript', 'eps': 'application/postscript',
    'sketch': 'application/octet-stream', 'fig': 'application/octet-stream',
    'xd': 'application/octet-stream', 'blend': 'application/x-blender',
    'dwg': 'image/vnd.dwg', 'dxf': 'image/vnd.dxf', 'stl': 'model/stl',
    'obj': 'model/obj', 'gltf': 'model/gltf+json', 'glb': 'model/gltf-binary',
    // Archives and images the first pass missed
    'zst': 'application/zstd', 'lz4': 'application/x-lz4',
    'tgz': 'application/gzip', 'cab': 'application/vnd.ms-cab-compressed',
    'jxl': 'image/jxl', 'jp2': 'image/jp2', 'cr2': 'image/x-canon-cr2',
    'nef': 'image/x-nikon-nef', 'arw': 'image/x-sony-arw',
    'orf': 'image/x-olympus-orf', 'rw2': 'image/x-panasonic-rw2',
    // Installers and packages
    'ipa': 'application/octet-stream', 'appx': 'application/vnd.ms-appx',
    'msix': 'application/msix', 'apks': 'application/octet-stream',
    'aab': 'application/octet-stream', 'pkg': 'application/octet-stream',
    'appimage': 'application/x-executable', 'snap': 'application/octet-stream',
    'flatpak': 'application/vnd.flatpak',
    // Data and config
    'db': 'application/vnd.sqlite3', 'sqlite': 'application/vnd.sqlite3',
    'parquet': 'application/vnd.apache.parquet', 'tsv': 'text/tab-separated-values',
    'env': 'text/plain', 'conf': 'text/plain', 'cfg': 'text/plain',
    'properties': 'text/plain', 'lock': 'text/plain', 'diff': 'text/x-diff',
    'patch': 'text/x-diff', 'gitignore': 'text/plain',
    // More code, all text. `.ts` is deliberately absent: it is already listed
    // as an MPEG transport stream above, and a video that will not play is a
    // worse outcome than a source file that opens in a text editor anyway.
    'tsx': 'text/plain', 'jsx': 'text/javascript',
    'vue': 'text/plain', 'svelte': 'text/plain', 'scss': 'text/x-scss',
    'less': 'text/plain', 'swift': 'text/plain', 'm': 'text/plain',
    'mm': 'text/plain', 'scala': 'text/plain', 'clj': 'text/plain',
    'ex': 'text/plain', 'exs': 'text/plain', 'erl': 'text/plain',
    'hs': 'text/plain', 'lua': 'text/plain', 'pl': 'text/plain',
    'r': 'text/plain', 'jl': 'text/plain', 'zig': 'text/plain',
    'gradle': 'text/plain', 'cmake': 'text/plain', 'dockerfile': 'text/plain',
    'ipynb': 'application/x-ipynb+json',
    // Office
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
