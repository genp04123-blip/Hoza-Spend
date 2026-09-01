import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/hoza_error.dart';
import '../../core/models/file_source.dart';
import '../../core/models/transfer.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/log.dart';
import '../connection/hoza_session.dart';
import '../protocol/control_message.dart';
import 'progress_tracker.dart';

/// Sends files over an established session.
///
/// The shape on the wire, per file: a `file` header line, then the contents as
/// a run of length-prefixed `chunk` frames, then a `fileDone` line carrying
/// the checksum. The checksum is a trailer rather than part of the offer so
/// the file is hashed *while* it streams - reading a 5 GB video twice to know
/// its digest up front would be absurd.
///
/// Nothing here is limited to a kind of file. A document, an installer, an
/// archive and a video all reach this class as a name, a byte count and
/// something that streams, and it treats them identically.
class TransferSender {
  TransferSender(
    this._session, {
    required List<TransferFile> files,
    required this.onProgress,
    required this.onPaused,
  })  : _files = List<TransferFile>.unmodifiable(files),
        id = Ids.next('t');

  static const String _tag = 'Transfer';

  /// How long to wait for the other side to answer the offer.
  static const Duration _offerWindow = Duration(seconds: 60);

  final String id;
  final HozaSession _session;
  final List<TransferFile> _files;
  final void Function(TransferProgress progress) onProgress;

  /// Fired whenever the transfer is held or released, by either user. The
  /// screen needs to say which it is, and the peer's pause arrives here rather
  /// than through anything the local user did.
  final void Function(bool paused) onPaused;

  late final ProgressTracker _tracker = ProgressTracker(
    totalBytes: _files.fold<int>(0, (int sum, TransferFile f) => sum + f.size),
    filesTotal: _files.length,
    onUpdate: onProgress,
  );

  StreamSubscription<ControlMessage>? _subscription;
  Completer<void>? _offerAnswer;
  Completer<HozaError?>? _result;
  bool _cancelled = false;
  HozaError? _failure;

  /// Non-null while the transfer is held. The streaming generator waits on it
  /// before every chunk, so a pause takes effect within one frame and leaves
  /// the connection, the partial file and the digest exactly as they were.
  Completer<void>? _paused;

  bool get isPaused => _paused != null;

  /// Why the transfer is stopping, at the points that only know *that* it is.
  ///
  /// A bare "Cancelled." is the right answer when this user pressed the
  /// button, and the wrong one when the other device ran out of space - the
  /// reason has already been recorded by then, so it is used in preference.
  HozaError get _abort => _failure ?? HozaError.cancelled;

  /// Runs the whole transfer. Completes normally on success, or throws a
  /// [HozaError] already phrased for the user.
  Future<void> run() async {
    _subscription = _session.messages.listen(_onMessage);
    try {
      await _awaitOfferAccepted();
      _tracker.start();

      for (final TransferFile file in _files) {
        if (_cancelled) throw _abort;
        await _sendFile(file);
        _tracker.completeFile();
      }

      _session.send(ControlMessage.end(id));
      await _awaitResult();
      Log.info(_tag, 'Sent ${_files.length} file(s)');
    } catch (error) {
      // Whatever went wrong on this side, the receiver is still waiting for
      // bytes. Telling it now means it deletes its partial file immediately
      // instead of sitting there until the liveness timeout.
      if (!_cancelled) {
        _cancelled = true;
        _session.send(ControlMessage.cancel(id, 'failed'));
      }
      rethrow;
    } finally {
      _tracker.stop();
      await _subscription?.cancel();
      _subscription = null;
    }
  }

  /// Asks the other side to stop. The receiver deletes its partial file.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _failure = HozaError.cancelled;
    // Released first: a paused transfer is parked inside the streaming
    // generator, and it has to wake up before it can notice it was cancelled.
    _release();
    _session.send(ControlMessage.cancel(id, 'cancelled'));
    _failOffer(HozaError.cancelled);
    _finishResult(HozaError.cancelled);
  }

  /// Holds the transfer where it is, at this user's request.
  ///
  /// Nothing is torn down: the socket stays up, the partial file on the other
  /// side stays put, and the digest keeps its state. The peer is told so its
  /// screen agrees, and both heartbeats carry on proving the link is alive.
  void pause() {
    if (_cancelled || _paused != null) return;
    _paused = Completer<void>();
    _session.send(ControlMessage.pause(id));
    Log.info(_tag, 'Paused');
    onPaused(true);
  }

  void resume() {
    if (_paused == null) return;
    _release();
    _session.send(ControlMessage.resume(id));
    Log.info(_tag, 'Resumed');
    onPaused(false);
  }

  /// Lets the streaming generator run again. Safe when not paused.
  void _release() {
    final Completer<void>? gate = _paused;
    _paused = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  /// Parks here for as long as either user keeps the transfer held. A loop
  /// rather than a single await, so a pause arriving as an earlier one is
  /// released still takes effect.
  Future<void> _awaitResume() async {
    Completer<void>? gate = _paused;
    while (gate != null) {
      await gate.future;
      gate = _paused;
    }
  }

  // Every completer is settled through these. Cancelling after the offer was
  // already answered, or a reject arriving next to a cancel, would otherwise
  // complete the same completer twice and throw a StateError from inside a
  // socket callback.
  void _acceptOffer() {
    final Completer<void>? answer = _offerAnswer;
    if (answer == null || answer.isCompleted) return;
    answer.complete();
  }

  void _failOffer(HozaError error) {
    final Completer<void>? answer = _offerAnswer;
    if (answer == null || answer.isCompleted) return;
    answer.completeError(error);
  }

  void _finishResult(HozaError? error) {
    final Completer<HozaError?>? result = _result;
    if (result == null || result.isCompleted) return;
    result.complete(error);
  }

  Future<void> _awaitOfferAccepted() {
    final Completer<void> answer = Completer<void>();
    _offerAnswer = answer;
    _session.send(ControlMessage.offer(id, _files));
    Log.info(_tag, 'Offered ${_files.length} file(s)');
    return answer.future.timeout(
      _offerWindow,
      onTimeout: () => throw HozaError.noAnswer,
    );
  }

  Future<void> _sendFile(TransferFile file) async {
    final FileSource? source = file.source;
    if (source == null) {
      throw const HozaError(
        HozaErrorKind.storage,
        "One of the files could not be opened.\nIt may have been moved or "
            'deleted.',
      );
    }

    _tracker.beginFile(file.name);
    _session.send(ControlMessage.fileHeader(file));

    // Hashed as it streams, so the file is read exactly once.
    final AccumulatorSink<Digest> digestOut = AccumulatorSink<Digest>();
    final ByteConversionSink digestIn = sha256.startChunkedConversion(digestOut);

    try {
      await _session.sendFramed(
        _exactly(source.openRead(), file.size, file.name, digestIn),
        onProgress: _tracker.addBytes,
      );
    } finally {
      digestIn.close();
    }

    if (_cancelled) throw _abort;
    _session.send(
      ControlMessage.fileDone(file.id, hex.encode(digestOut.events.single.bytes)),
    );
  }

  /// Guarantees the receiver gets exactly the byte count it was promised, in
  /// frames no larger than one chunk.
  ///
  /// A file that shrank since selection would otherwise leave the receiver
  /// waiting forever for bytes that will never arrive, and one that grew would
  /// have its tail parsed as control lines. Both are real: a video still being
  /// written, a document saved again mid-transfer.
  ///
  /// Re-slicing to [AppConstants.chunkSize] matters beyond tidiness. A source
  /// hands over whatever size it likes - a file read from disk gives about
  /// 64 KB, a source backed by a single read gives the lot at once - and the
  /// frame size is what bounds the receiver's allocation and how quickly a
  /// pause or a cancel bites.
  Stream<List<int>> _exactly(
    Stream<List<int>> source,
    int size,
    String name,
    ByteConversionSink digest,
  ) async* {
    int sent = 0;
    await for (final List<int> chunk in source) {
      if (sent >= size) break;
      int offset = 0;
      while (offset < chunk.length && sent < size) {
        // Before the bytes, not after: a paused transfer stops having sent
        // every frame it announced, never halfway through one.
        await _awaitResume();
        if (_cancelled) throw _abort;

        final int take = math.min(
          AppConstants.chunkSize,
          math.min(chunk.length - offset, size - sent),
        );
        final List<int> slice = offset == 0 && take == chunk.length
            ? chunk
            : chunk.sublist(offset, offset + take);
        digest.add(slice);
        offset += take;
        sent += take;
        yield slice;
      }
    }
    if (sent < size) {
      throw HozaError(
        HozaErrorKind.storage,
        '"$name" changed while it was being sent.\nTry again.',
        detail: 'expected $size bytes, read $sent',
      );
    }
  }

  Future<void> _awaitResult() {
    final Completer<HozaError?> result = Completer<HozaError?>();
    _result = result;
    return result.future
        .timeout(_offerWindow, onTimeout: () => HozaError.noAnswer)
        .then((HozaError? error) {
      if (error != null) throw error;
    });
  }

  void _onMessage(ControlMessage message) {
    switch (message.type) {
      case ControlType.offerAccept:
        _acceptOffer();

      case ControlType.offerReject:
        // "Busy" is not "no". The receiver is connected to more than one
        // device and one of the others got there first, and telling this user
        // their transfer was declined would blame a person for a queue.
        _failOffer(
          message.reason == 'busy'
              ? HozaError.deviceTransferring
              : HozaError.declined,
        );

      case ControlType.pause:
        // The receiving user pressed pause. Nothing is sent back: they already
        // know, and an echo would only race their own resume.
        if (_cancelled || _paused != null) return;
        _paused = Completer<void>();
        Log.info(_tag, 'Paused by the other device');
        onPaused(true);

      case ControlType.resume:
        if (_paused == null) return;
        _release();
        Log.info(_tag, 'Resumed by the other device');
        onPaused(false);

      case ControlType.cancel:
        _cancelled = true;
        _failure = const HozaError(
          HozaErrorKind.cancelled,
          'The other device cancelled the transfer.',
        );
        _release();
        _failOffer(_failure!);
        _finishResult(_failure);

      case ControlType.result:
        if (message.isOk) {
          _finishResult(null);
          return;
        }
        final HozaError failure = HozaError(
          HozaErrorKind.unknown,
          "The other device couldn't save the files.\nTry again.",
          detail: message.reason,
        );
        // A failure can arrive long before the end of the transfer - a full
        // disk, or a checksum that did not match on the first of five files -
        // and at that point the receiver has stopped writing. Without this the
        // sender would stream every remaining byte into a peer that is only
        // throwing them away, and only notice once it asked for a result.
        _cancelled = true;
        _failure = failure;
        _release();
        _failOffer(failure);
        _finishResult(failure);

      default:
        break;
    }
  }
}
