import 'file_source.dart';

/// Which way a transfer is going, from this device's point of view.
enum TransferDirection { send, receive }

/// Lifecycle of one transfer session.
enum TransferStatus {
  /// Queued locally, nothing on the wire yet.
  pending,

  /// Offer sent, waiting for the other side to accept or reject.
  awaitingApproval,

  connecting,
  inProgress,
  completed,

  /// Stopped by this user.
  cancelled,

  /// The other device declined.
  rejected,

  /// Something went wrong. [TransferRecord.failureReason] carries text that is
  /// safe to show a user.
  failed;

  bool get isFinished =>
      this == completed ||
      this == cancelled ||
      this == rejected ||
      this == failed;

  bool get isActive => this == connecting || this == inProgress;
}

/// Broad file kind, used to pick an icon and decide whether to try a thumbnail.
enum FileKind { image, video, audio, document, archive, other }

/// One file inside a transfer.
class TransferFile {
  const TransferFile({
    required this.id,
    required this.name,
    required this.size,
    required this.kind,
    this.source,
    this.savedPath,
    this.openUri,
    this.checksum,
  });

  /// Unique within its transfer; used to match incoming chunks to a file.
  final String id;

  final String name;
  final int size;
  final FileKind kind;

  /// How to read the file when sending. Null for a history entry, which only
  /// remembers that a transfer happened.
  final FileSource? source;

  /// Convenience for display and de-duplication. Null on Android, where the
  /// picker gives a storage-access URI instead of a path.
  String? get sourcePath => source?.path;

  /// Where it was written when receiving. Null until the transfer completes.
  ///
  /// On Android 10 and up this is where the file *reads* as being -
  /// `Download/HozaSend/name.jpg` - rather than somewhere the app can reach.
  /// Under scoped storage a published file has no path the app may open; see
  /// [openUri].
  final String? savedPath;

  /// The handle another app can be handed to open this file.
  ///
  /// On Android 10 and up that is the MediaStore entry the file was published
  /// as, which is the only way back to it once it has left the app's own
  /// folder. Null everywhere else, where [savedPath] is a real path and is
  /// handle enough.
  final String? openUri;

  /// SHA-256 of the contents, checked by the receiver before the partial file
  /// is renamed to its final name.
  final String? checksum;

  Map<String, Object?> toWire() => <String, Object?>{
        'id': id,
        'name': name,
        'size': size,
        'kind': kind.name,
        if (checksum != null) 'checksum': checksum,
      };

  TransferFile copyWith({
    String? savedPath,
    String? openUri,
    String? checksum,
  }) {
    return TransferFile(
      id: id,
      name: name,
      size: size,
      kind: kind,
      source: source,
      savedPath: savedPath ?? this.savedPath,
      openUri: openUri ?? this.openUri,
      checksum: checksum ?? this.checksum,
    );
  }
}

/// A snapshot of an in-flight transfer. Recomputed on a throttle, not per chunk.
class TransferProgress {
  const TransferProgress({
    required this.bytesTransferred,
    required this.totalBytes,
    required this.bytesPerSecond,
    this.currentFileName,
    this.filesDone = 0,
    this.filesTotal = 1,
  });

  static const TransferProgress zero = TransferProgress(
    bytesTransferred: 0,
    totalBytes: 0,
    bytesPerSecond: 0,
  );

  final int bytesTransferred;
  final int totalBytes;
  final double bytesPerSecond;
  final String? currentFileName;
  final int filesDone;
  final int filesTotal;

  /// 0.0 to 1.0. A zero total means "unknown", which reads as 0 rather than NaN.
  double get fraction {
    if (totalBytes <= 0) return 0;
    return (bytesTransferred / totalBytes).clamp(0.0, 1.0);
  }

  int get percent => (fraction * 100).round();

  /// Null while the speed is not yet meaningful, so the UI can show a dash
  /// instead of a wildly wrong estimate in the first few hundred milliseconds.
  Duration? get remaining {
    if (bytesPerSecond <= 0 || totalBytes <= 0) return null;
    final int left = totalBytes - bytesTransferred;
    if (left <= 0) return Duration.zero;
    return Duration(seconds: (left / bytesPerSecond).ceil());
  }
}

/// A completed or in-flight transfer, as stored in history.
class TransferRecord {
  const TransferRecord({
    required this.id,
    required this.direction,
    required this.deviceName,
    required this.files,
    required this.status,
    required this.startedAt,
    this.completedAt,
    this.failureReason,
  });

  final String id;
  final TransferDirection direction;
  final String deviceName;
  final List<TransferFile> files;
  final TransferStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;

  /// User-facing text only. Raw socket errors are logged, never stored here.
  final String? failureReason;

  int get totalBytes =>
      files.fold<int>(0, (int sum, TransferFile f) => sum + f.size);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'direction': direction.name,
        'deviceName': deviceName,
        'status': status.name,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'failureReason': failureReason,
        'files': files
            .map((TransferFile f) => <String, Object?>{
                  'id': f.id,
                  'name': f.name,
                  'size': f.size,
                  'kind': f.kind.name,
                  'savedPath': f.savedPath,
                  'openUri': f.openUri,
                })
            .toList(),
      };

  static TransferRecord fromJson(Map<String, Object?> json) {
    final List<Object?> rawFiles =
        json['files'] as List<Object?>? ?? const <Object?>[];
    return TransferRecord(
      id: json['id'] as String? ?? '',
      direction: TransferDirection.values.firstWhere(
        (TransferDirection d) => d.name == json['direction'],
        orElse: () => TransferDirection.receive,
      ),
      deviceName: json['deviceName'] as String? ?? 'Unknown device',
      status: TransferStatus.values.firstWhere(
        (TransferStatus s) => s.name == json['status'],
        orElse: () => TransferStatus.failed,
      ),
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      failureReason: json['failureReason'] as String?,
      files: rawFiles
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> f) => TransferFile(
                id: f['id'] as String? ?? '',
                name: f['name'] as String? ?? 'file',
                size: f['size'] as int? ?? 0,
                kind: FileKind.values.firstWhere(
                  (FileKind k) => k.name == f['kind'],
                  orElse: () => FileKind.other,
                ),
                savedPath: f['savedPath'] as String?,
                openUri: f['openUri'] as String?,
              ))
          .toList(),
    );
  }
}
