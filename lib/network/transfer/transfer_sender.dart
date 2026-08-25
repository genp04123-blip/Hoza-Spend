import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

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
/// The shape on the wire, per file: a `file` header line, exactly `size` raw
/// bytes, then a `fileDone` line carrying the checksum. The checksum is a
/// trailer rather than part of the offer so the file is hashed *while* it
/// streams - reading a 5 GB video twice to know its digest up front would be
/// absurd.
class TransferSender {
  TransferSender(
    this._session, {
    required List<TransferFile> files,
    required this.onProgress,
  })  : _files = List<TransferFile>.unmodifiable(files),
        id = Ids.next('t');

  static const String _tag = 'Transfer';

  /// How long to wait for the other side to answer the offer.
  static const Duration _offerWindow = Duration(seconds: 60);

  final String id;
  final HozaSession _session;
  final List<TransferFile> _files;
  final void Function(TransferProgress progress) onProgress;

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

  /// Runs the whole transfer. Completes normally on success, or throws a
  /// [HozaError] already phrased for the user.
  Future<void> run() async {
    _subscription = _session.messages.listen(_onMessage);
    try {
      await _awaitOfferAccepted();
      _tracker.start();

      for (final TransferFile file in _files) {
        if (_cancelled) throw HozaError.cancelled;
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
    _session.send(ControlMessage.cancel(id, 'cancelled'));
    _failOffer(HozaError.cancelled);
    _finishResult(HozaError.cancelled);
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
      await _session.sendBinary(
        _exactly(source.openRead(), file.size, file.name, digestIn),
        onProgress: _tracker.addBytes,
      );
    } finally {
      digestIn.close();
    }

    if (_cancelled) throw HozaError.cancelled;
    _session.send(
      ControlMessage.fileDone(file.id, hex.encode(digestOut.events.single.bytes)),
    );
  }

  /// Guarantees the receiver gets exactly the byte count it was promised.
  ///
  /// A file that shrank since selection would otherwise leave the receiver
  /// waiting forever for bytes that will never arrive, and one that grew would
  /// have its tail parsed as control lines. Both are real: a video still being
  /// written, a document saved again mid-transfer.
  Stream<List<int>> _exactly(
    Stream<List<int>> source,
    int size,
    String name,
    ByteConversionSink digest,
  ) async* {
    int sent = 0;
    await for (final List<int> chunk in source) {
      if (_cancelled) throw HozaError.cancelled;
      if (sent >= size) break;
      final int take = math.min(chunk.length, size - sent);
      final List<int> slice =
          take == chunk.length ? chunk : chunk.sublist(0, take);
      digest.add(slice);
      sent += take;
      yield slice;
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
        _failOffer(HozaError.declined);

      case ControlType.cancel:
        _cancelled = true;
        _failure = const HozaError(
          HozaErrorKind.cancelled,
          'The other device cancelled the transfer.',
        );
        _failOffer(_failure!);
        _finishResult(_failure);

      case ControlType.result:
        _finishResult(
          message.isOk
              ? null
              : HozaError(
                  HozaErrorKind.unknown,
                  "The other device couldn't save the files.\nTry again.",
                  detail: message.reason,
                ),
        );

      default:
        break;
    }
  }
}
