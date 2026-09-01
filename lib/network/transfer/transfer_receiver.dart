import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

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
    required this.subPath,
    required this.sink,
  });

  final TransferFile file;
  final String finalPath;
  final File partial;

  /// Where inside the download folder this file lives, sanitised, or empty for
  /// a file that was not part of a folder selection.
  final String subPath;

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
///
/// A file arrives as a `file` header, a run of `chunk` frames, and a `fileDone`
/// trailer. Nothing here inspects what kind of file it is: a name, a byte count
/// and a digest are the whole of what a file means at this level, which is why
/// a spreadsheet, an installer and a video are all handled by the same code.
///
/// Every step that touches the file being written runs on one queue, in the
/// order the messages arrived. That is not tidiness. Messages arrive
/// synchronously from the socket and the work they cause is asynchronous, and
/// several of them routinely land in a single read - `fileDone` for one file
/// and the `file` header for the next are written back to back by the sender
/// and almost always arrive together. Without a queue the trailer for one file
/// resolves against the handle of the one after it, and the wrong file is
/// verified, renamed and reported.
class TransferReceiver {
  TransferReceiver(
    this._session, {
    required this.downloadPath,
    required this.confirm,
    required this.onProgress,
    required this.onStarted,
    required this.onPaused,
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

  /// Fired when the transfer is held or released, by either user.
  final void Function(bool paused) onPaused;

  /// Fired exactly once per transfer: null on success, otherwise the reason.
  final void Function(String transferId, List<TransferFile> saved,
      HozaError? error) onFinished;

  StreamSubscription<ControlMessage>? _subscription;
  ProgressTracker? _tracker;

  /// The file currently being written, or null between files.
  ///
  /// Only ever read and written from inside [_enqueue], which is what makes
  /// "currently" a well-defined idea here.
  _ActiveFile? _active;

  /// Everything that touches [_active], in arrival order. See the class note.
  Future<void> _queue = Future<void>.value();

  /// A file is arriving that there is nowhere to put. Its bytes are read and
  /// dropped rather than ignored: the frame lengths have to be consumed either
  /// way, or the connection loses its place in the stream.
  bool _draining = false;

  /// Held by one of the two users. Only a display state on this side - the
  /// sender is what stops, and it stops on its own byte count.
  bool _paused = false;

  String? _transferId;
  final List<TransferFile> _saved = <TransferFile>[];
  int _sinceFlush = 0;
  bool _finished = false;

  bool get isReceiving => _transferId != null;

  bool get isPaused => _paused;

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _finished = true;
    _enqueue(_abandon);
  }

  /// Holds the transfer at this user's request.
  ///
  /// The sender is the side that actually stops; this asks it to. Nothing is
  /// closed and the partial file stays exactly where it is, so resuming costs
  /// nothing and loses nothing.
  void pause() {
    final String? id = _transferId;
    if (id == null || _finished || _paused) return;
    _paused = true;
    _tracker?.setPaused(true);
    _session.send(ControlMessage.pause(id));
    Log.info(_tag, 'Paused');
    onPaused(true);
  }

  void resume() {
    final String? id = _transferId;
    if (id == null || _finished || !_paused) return;
    _paused = false;
    _tracker?.setPaused(false);
    _session.send(ControlMessage.resume(id));
    Log.info(_tag, 'Resumed');
    onPaused(false);
  }

  /// Stops the transfer at this user's request and tells the sender.
  void cancel() {
    final String? id = _transferId;
    if (id == null) return;
    _session.send(ControlMessage.cancel(id, 'cancelled'));
    _complete(HozaError.cancelled);
  }

  /// Runs [step] after everything already queued.
  ///
  /// A failure anywhere on the queue fails the transfer and is swallowed here,
  /// so one bad file cannot leave an unhandled async error behind or break the
  /// queue for the steps that follow it - those find [_finished] set and do
  /// nothing, which is what should happen after a transfer has failed.
  void _enqueue(Future<void> Function() step) {
    _queue = _queue.then((_) => step()).catchError(
      (Object error, StackTrace stack) {
        _complete(HozaError.from(error));
      },
    );
  }

  void _onMessage(ControlMessage message) {
    switch (message.type) {
      case ControlType.offer:
        _onOffer(message);

      case ControlType.file:
        _enqueue(() => _openFile(message));

      case ControlType.chunk:
        _onChunk(message);

      case ControlType.fileDone:
        _enqueue(() => _finishFile(message));

      case ControlType.end:
        _enqueue(_onEnd);

      case ControlType.pause:
        // The sending user pressed pause. Nothing is sent back: they already
        // know, and an echo would only race their own resume.
        if (_transferId == null || _paused) return;
        _paused = true;
        _tracker?.setPaused(true);
        Log.info(_tag, 'Paused by the other device');
        onPaused(true);

      case ControlType.resume:
        if (_transferId == null || !_paused) return;
        _paused = false;
        _tracker?.setPaused(false);
        Log.info(_tag, 'Resumed by the other device');
        onPaused(false);

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
    _paused = false;
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
  /// before the reader looks at the next byte, or the chunk's own contents get
  /// parsed as control lines.
  ///
  /// The bytes themselves are only *routed* here. Writing them is queued, so
  /// they cannot reach the disk before the file they belong to has been
  /// opened, or after it has been closed.
  void _onChunk(ControlMessage message) {
    final int? length = message.chunkLength;
    if (length == null) {
      // There is no way to skip a run whose length we were not told, so the
      // connection has lost its place and cannot get it back.
      Log.warn(_tag, 'Refusing a chunk header with no usable length');
      _complete(
        const HozaError(
          HozaErrorKind.network,
          'The other device sent something this version cannot read.',
          detail: 'bad chunk length',
        ),
      );
      return;
    }

    _session.expectBinary(
      length,
      onBytes: (List<int> bytes) => _enqueue(() => _write(bytes)),
      // Finalisation is driven by the fileDone trailer, which carries the
      // checksum; there is nothing to do at the last byte of a chunk.
      onDone: () {},
    );
  }

  Future<void> _openFile(ControlMessage message) async {
    final TransferFile? file = message.fileHeaderValue;
    if (file == null) return;

    if (_transferId == null || _finished) {
      // Nothing to write into - the transfer already failed or was cancelled -
      // but the sender is mid-stream and those bytes are arriving either way.
      // Reading and dropping them keeps the framing intact, so the connection
      // survives to be used again.
      Log.info(_tag, 'Draining "${file.name}"; no transfer is active');
      _draining = true;
      return;
    }

    _draining = false;
    _tracker?.beginFile(file.name);
    _sinceFlush = 0;

    // A file sent from inside a folder keeps its place in that folder. The
    // relative path came from another device, so every segment of it is
    // sanitised before any of it is allowed to become a directory.
    final String subPath = StorageService.safeSubDirectory(file.relativePath);
    final Directory directory = await StorageService.ensureDirectory(
      subPath.isEmpty ? downloadPath : p.join(downloadPath, subPath),
    );
    final String finalPath =
        await StorageService.uniquePath(directory, file.name);
    final File partial = File('$finalPath${AppConstants.partialSuffix}');

    _active = _ActiveFile(
      file: file,
      finalPath: finalPath,
      partial: partial,
      subPath: subPath,
      sink: partial.openWrite(),
    );
  }

  Future<void> _write(List<int> bytes) async {
    if (_draining || _finished) return;
    final _ActiveFile? active = _active;
    // A chunk with no file in front of it is a peer talking nonsense. The
    // bytes have already been consumed, which is what keeps the framing whole.
    if (active == null) return;

    active.sink.add(bytes);
    active.digestIn.add(bytes);
    active.written += bytes.length;
    _tracker?.addBytes(bytes.length);

    _sinceFlush += bytes.length;
    if (_sinceFlush < _flushThreshold) return;
    _sinceFlush = 0;

    // Reading stops for the length of the flush, so a fast network cannot
    // queue data faster than storage will take it. Awaited on the queue, so
    // nothing else is written into this sink while it drains.
    _session.pauseInput();
    try {
      await active.sink.flush();
    } catch (error) {
      Log.warn(_tag, 'Flush failed: $error');
    }
    _session.resumeInput();
  }

  Future<void> _finishFile(ControlMessage message) async {
    if (_draining) {
      _draining = false;
      return;
    }

    final _ActiveFile? active = _active;
    _active = null;
    if (active == null || _finished) return;

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

      // The file keeps the age it had on the other device, so a folder of
      // photos still sorts by when they were taken rather than all landing at
      // the same second. Best effort: a filesystem that will not take the
      // timestamp is no reason to fail a transfer that arrived intact.
      if (active.file.modifiedAt case final DateTime modified) {
        try {
          await File(active.finalPath).setLastModified(modified);
        } catch (error) {
          Log.info(_tag, 'Could not restore the timestamp: $error');
        }
      }

      // On Android the file is now complete and verified in the app's own
      // folder, so it can be handed to MediaStore for Downloads/HozaSend. A
      // failure here is not a failed transfer - the file exists either way, so
      // the path we already have stands.
      String savedPath = active.finalPath;
      String? openUri;
      if (DownloadsPublisher.isSupported) {
        final PublishedFile? published = await DownloadsPublisher.publish(
          savedPath,
          subPath: active.subPath,
          modifiedAt: active.file.modifiedAt,
        );
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
    }
  }

  Future<void> _onEnd() async {
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
    _paused = false;
    _tracker?.stop();
    _tracker = null;

    if (error != null) {
      _session.send(ControlMessage.result(id, failure: error.kind.name));
      // Queued rather than run now: the file may be mid-write, and closing a
      // sink out from under a write in flight is how a cancel turns into an
      // exception nobody asked for.
      _enqueue(_abandon);
    }
    onFinished(id, List<TransferFile>.unmodifiable(_saved), error);
  }

  /// Throws away a partial file. A failed transfer must not leave debris in the
  /// user's download folder.
  Future<void> _abandon() async {
    final _ActiveFile? active = _active;
    _active = null;
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
