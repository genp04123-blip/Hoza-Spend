import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/hoza_error.dart';
import '../../core/models/file_source.dart';
import '../../core/models/transfer.dart';
import '../../core/services/downloads_publisher.dart';
import '../../core/utils/log.dart';
import '../../data/local/storage_service.dart';
import '../connection/hoza_session.dart';
import '../protocol/control_message.dart';
import 'progress_tracker.dart';

/// One file being written to disk.
class _ActiveFile {
  _ActiveFile({
    required this.file,
    required this.finalPath,
    required this.partial,
    required this.sink,
  });

  final TransferFile file;
  final String finalPath;
  final File partial;
  final IOSink sink;

  final AccumulatorSink<Digest> digestOut = AccumulatorSink<Digest>();
  late final ByteConversionSink digestIn =
      sha256.startChunkedConversion(digestOut);

  int written = 0;
}

/// Receives files over an established session and writes them to storage.
///
/// Bytes go to a `.hozapart` file and are hashed on the way past. Only once the
/// byte count *and* the checksum both match is it renamed to its real name, so
/// a truncated or corrupted file never appears in the download folder looking
/// finished.
class TransferReceiver {
  TransferReceiver(
    this._session, {
    required this.downloadPath,
    required this.confirm,
    required this.onProgress,
    required this.onStarted,
    required this.onFinished,
  }) {
    _subscription = _session.messages.listen(_onMessage);
  }

  static const String _tag = 'Transfer';

  /// Bytes written between disk flushes. Reading is paused across each flush,
  /// which is what stops a fast network from queueing data faster than storage
  /// can take it.
  static const int _flushThreshold = 8 * 1024 * 1024;

  final HozaSession _session;
  final String downloadPath;

  /// Asks whether to take these files. Resolving false declines politely; the
  /// auto-accept setting is handled by the caller, not here.
  final Future<bool> Function(List<TransferFile> files) confirm;

  final void Function(TransferProgress progress) onProgress;

  /// Fired when an offer has been accepted, so the UI can open the transfer
  /// screen with the real file list.
  final void Function(String transferId, List<TransferFile> files) onStarted;

  /// Fired exactly once per transfer: null on success, otherwise the reason.
  final void Function(String transferId, List<TransferFile> saved,
      HozaError? error) onFinished;

  StreamSubscription<ControlMessage>? _subscription;
  ProgressTracker? _tracker;
  _ActiveFile? _active;

  /// The file currently being opened. Opening is async while the bytes are
  /// already arriving, so the trailer handler waits on this rather than on
  /// [_active], which may not be set yet for a small file.
  Future<_ActiveFile?>? _opening;

  /// Serialises finalisation against the messages that follow it. `fileDone`
  /// and `end` routinely arrive in the same socket chunk, so without this the
  /// success result would be sent before the last file had been verified and
  /// renamed.
  Future<void> _finalising = Future<void>.value();

  String? _transferId;
  final List<TransferFile> _saved = <TransferFile>[];
  int _sinceFlush = 0;
  bool _finished = false;

  bool get isReceiving => _transferId != null;

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_abandon());
  }

  /// Stops the transfer at this user's request and tells the sender.
  void cancel() {
    final String? id = _transferId;
    if (id == null) return;
    _session.send(ControlMessage.cancel(id, 'cancelled'));
    _complete(HozaError.cancelled);
  }

  void _onMessage(ControlMessage message) {
    switch (message.type) {
      case ControlType.offer:
        _onOffer(message);
      case ControlType.file:
        _onFileHeader(message);
      case ControlType.fileDone:
        _finalising = _finalising.then((_) => _onFileDone(message));
      case ControlType.end:
        _finalising = _finalising.then((_) => _onEnd());
      case ControlType.cancel:
        if (_transferId == null) return;
        Log.info(_tag, 'Sender cancelled');
        _complete(
          const HozaError(
            HozaErrorKind.cancelled,
            'The other device cancelled the transfer.',
          ),
        );
      default:
        break;
    }
  }

  void _onOffer(ControlMessage message) {
    final String? id = message.transferId;
    final List<TransferFile> files = message.offeredFiles;
    if (id == null || files.isEmpty) return;

    if (_transferId != null) {
      _session.send(ControlMessage.offerReject(id, 'busy'));
      return;
    }

    // Claimed before the user is asked, so a second offer arriving while the
    // prompt is still up is refused rather than stacked behind it.
    _transferId = id;
    _finished = false;
    _saved.clear();

    // Nothing arrives while this is pending: the sender is waiting on the
    // answer before it writes a single byte.
    unawaited(
      confirm(files).then((bool accepted) {
        // The sender may have given up, or the session may have dropped, while
        // the prompt was on screen.
        if (_transferId != id) return;

        if (!accepted) {
          Log.info(_tag, 'Declined ${files.length} file(s)');
          _session.send(ControlMessage.offerReject(id, 'declined'));
          _transferId = null;
          return;
        }

        _tracker = ProgressTracker(
          totalBytes:
              files.fold<int>(0, (int sum, TransferFile f) => sum + f.size),
          filesTotal: files.length,
          onUpdate: onProgress,
        )..start();

        Log.info(_tag, 'Receiving ${files.length} file(s)');
        _session.send(ControlMessage.offerAccept(id));
        onStarted(id, files);
      }),
    );
  }

  /// Runs synchronously, and must: [HozaSession.expectBinary] has to be armed
  /// before the reader looks at the next byte, or the file's own contents get
  /// parsed as control lines.
  void _onFileHeader(ControlMessage message) {
    final TransferFile? file = message.fileHeaderValue;
    if (file == null || _transferId == null) return;

    _tracker?.beginFile(file.name);
    _sinceFlush = 0;

    // Opening the sink is async, but arming the reader cannot wait: the bytes
    // are already on the wire. Anything that lands before the sink exists is
    // held here and written the moment it does.
    final List<List<int>> pending = <List<int>>[];
    _ActiveFile? ready;

    _opening = _open(file).then<_ActiveFile?>((_ActiveFile active) {
      ready = active;
      _active = active;
      for (final List<int> chunk in pending) {
        _writeBytes(active, chunk);
      }
      pending.clear();
      return active;
    }).catchError((Object error, StackTrace stack) {
      // Reported here rather than left on the future, so it can never surface
      // as an unhandled async error if the trailer never arrives.
      _complete(HozaError.from(error));
      return null;
    });

    _session.expectBinary(
      file.size,
      onBytes: (List<int> bytes) {
        final _ActiveFile? active = ready;
        if (active == null) {
          pending.add(bytes);
          return;
        }
        _writeBytes(active, bytes);
      },
      // Finalisation is driven by the fileDone trailer, which carries the
      // checksum; there is nothing to do at the last byte.
      onDone: () {},
    );
  }

  Future<_ActiveFile> _open(TransferFile file) async {
    final Directory directory =
        await StorageService.ensureDirectory(downloadPath);
    final String finalPath =
        await StorageService.uniquePath(directory, file.name);
    final File partial = File('$finalPath${AppConstants.partialSuffix}');
    return _ActiveFile(
      file: file,
      finalPath: finalPath,
      partial: partial,
      sink: partial.openWrite(),
    );
  }

  void _writeBytes(_ActiveFile active, List<int> bytes) {
    active.sink.add(bytes);
    active.digestIn.add(bytes);
    active.written += bytes.length;
    _tracker?.addBytes(bytes.length);

    _sinceFlush += bytes.length;
    if (_sinceFlush < _flushThreshold) return;
    _sinceFlush = 0;
    _session.pauseInput();
    unawaited(_flushAndResume(active.sink));
  }

  Future<void> _flushAndResume(IOSink sink) async {
    try {
      await sink.flush();
    } catch (error) {
      Log.warn(_tag, 'Flush failed: $error');
    }
    _session.resumeInput();
  }

  Future<void> _onFileDone(ControlMessage message) async {
    final Future<_ActiveFile?>? opening = _opening;
    if (opening == null || _finished) return;
    _opening = null;

    // Reading pauses while the file is closed and verified; the sender's next
    // header can wait a few milliseconds.
    _session.pauseInput();
    final _ActiveFile? active = await opening;
    // A cancel can land during that await, in which case _abandon has already
    // dealt with the partial file and there is nothing to verify.
    if (active == null || _finished) {
      _session.resumeInput();
      return;
    }
    _active = null;

    try {
      await active.sink.flush();
      await active.sink.close();
      active.digestIn.close();

      if (active.written != active.file.size) {
        throw HozaError(
          HozaErrorKind.network,
          '"${active.file.name}" did not arrive completely.\nTry again.',
          detail: 'expected ${active.file.size}, wrote ${active.written}',
        );
      }

      final String actual = hex.encode(active.digestOut.events.single.bytes);
      final String? expected = message.checksum;
      if (expected != null && expected != actual) {
        throw HozaError(
          HozaErrorKind.network,
          '"${active.file.name}" arrived damaged.\nTry again.',
          detail: 'checksum mismatch',
        );
      }

      // Only now does it get its real name. Until this rename, nothing in the
      // download folder looks like a finished file.
      await active.partial.rename(active.finalPath);

      // On Android the file is now complete and verified in the app's own
      // folder, so it can be handed to MediaStore for Downloads/HozaSend. A
      // failure here is not a failed transfer - the file exists either way, so
      // the path we already have stands.
      String savedPath = active.finalPath;
      String? openUri;
      if (DownloadsPublisher.isSupported) {
        final PublishedFile? published =
            await DownloadsPublisher.publish(savedPath);
        if (published != null) {
          savedPath = published.location;
          // The handle that reopens it later, kept because a published file
          // has no path the app is allowed to walk back to.
          openUri = published.uri;
        }
      }

      _saved.add(
        active.file.copyWith(
          savedPath: savedPath,
          openUri: openUri,
          checksum: actual,
        ),
      );
      _tracker?.completeFile();
      Log.info(_tag, 'Saved ${active.file.name}');
    } catch (error) {
      await _deleteQuietly(active.partial);
      _complete(HozaError.from(error));
    } finally {
      _session.resumeInput();
    }
  }

  void _onEnd() {
    final String? id = _transferId;
    if (id == null || _finished) return;
    _session.send(ControlMessage.result(id));
    _complete(null);
  }

  void _complete(HozaError? error) {
    final String? id = _transferId;
    if (id == null || _finished) return;
    _finished = true;
    _transferId = null;
    _tracker?.stop();
    _tracker = null;

    if (error != null) {
      _session.send(ControlMessage.result(id, failure: error.kind.name));
      unawaited(_abandon());
    }
    onFinished(id, List<TransferFile>.unmodifiable(_saved), error);
  }

  /// Throws away a partial file. A failed transfer must not leave debris in the
  /// user's download folder.
  Future<void> _abandon() async {
    final _ActiveFile? active = _active;
    _active = null;
    _opening = null;
    if (active == null) return;
    try {
      await active.sink.close();
    } catch (_) {
      // Already broken; the delete below is what matters.
    }
    await _deleteQuietly(active.partial);
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (error) {
      Log.warn(_tag, 'Could not remove partial file: $error');
    }
  }
}

/// The saved copy of a received file, so history and "open file" have a handle.
FileSource savedSource(String path) => PathFileSource(path);
