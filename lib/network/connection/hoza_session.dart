import 'dart:async';
import 'dart:io';

import '../../core/errors/hoza_error.dart';
import '../../core/models/hoza_device.dart';
import '../../core/utils/log.dart';
import '../protocol/control_message.dart';
import '../protocol/line_reader.dart';

/// One live connection between two devices.
///
/// Owns the socket, the framing and the heartbeat. It carries the whole
/// conversation: control lines, and the raw file bytes that follow a `file`
/// header. Everything above it deals in [ControlMessage] and never touches a
/// socket directly.
class HozaSession {
  HozaSession(
    this._socket, {
    required this.remote,
    required this.code,
    required this.isInitiator,
  }) {
    _subscription = _socket.listen(
      _onData,
      onError: _onSocketError,
      onDone: _onSocketDone,
      cancelOnError: false,
    );
    _lastInbound = DateTime.now();
    _heartbeat = Timer.periodic(_pingInterval, (_) => _onHeartbeat());
  }

  static const String _tag = 'Connection';

  /// How often a ping goes out. TCP alone will not tell us the Wi-Fi dropped;
  /// without this a session can sit "connected" forever against a dead peer.
  static const Duration _pingInterval = Duration(seconds: 5);

  /// Silence longer than this means the peer is gone. File bytes count as
  /// traffic, so a long transfer never trips this.
  static const Duration _livenessTimeout = Duration(seconds: 15);

  /// Unflushed bytes allowed while streaming a file. Flushing every chunk
  /// would stall on the socket buffer constantly; never flushing would let a
  /// fast disk queue a whole file in memory ahead of a slow network.
  static const int _flushThreshold = 512 * 1024;

  final Socket _socket;

  /// The device at the other end.
  HozaDevice remote;

  /// The six digit code both users can compare. Mutable because the receiving
  /// side only learns it from the peer's hello, one message after the socket
  /// already exists.
  String code;

  /// True if this device started the connection.
  final bool isInitiator;

  final LineReader _reader = LineReader();

  /// Synchronous on purpose. The handler for a `file` header has to call
  /// [expectBinary] before the reader looks at another byte, and an async
  /// broadcast controller would deliver it a microtask too late - by which
  /// point the file's own bytes would have been parsed as text.
  final StreamController<ControlMessage> _messages =
      StreamController<ControlMessage>.broadcast(sync: true);

  final Completer<HozaError?> _closed = Completer<HozaError?>();

  StreamSubscription<List<int>>? _subscription;
  Timer? _heartbeat;
  DateTime _lastInbound = DateTime.now();
  bool _disposed = false;
  bool _inputPaused = false;
  bool _writingBinary = false;

  /// Control messages from the peer. Pings and pongs are handled internally and
  /// never surface here.
  Stream<ControlMessage> get messages => _messages.stream;

  /// Completes when the session ends: null for an orderly close, otherwise the
  /// reason, already phrased for a user.
  Future<HozaError?> get closed => _closed.future;

  bool get isOpen => !_disposed;

  void send(ControlMessage message) {
    if (_disposed) return;
    try {
      _socket.add(message.encode());
    } on SocketException catch (error) {
      Log.warn(_tag, 'Send failed: ${error.message}');
      _finish(HozaError.lost);
    }
  }

  /// Routes the next [length] bytes to [onBytes] rather than parsing them as
  /// control lines. Must be called from a `file` header handler, synchronously.
  void expectBinary(
    int length, {
    required void Function(List<int> bytes) onBytes,
    required void Function() onDone,
  }) {
    _reader.expectBinary(length, onBytes: onBytes, onDone: onDone);
  }

  /// Streams a file onto the wire.
  ///
  /// Heartbeats are suppressed for the duration: a ping line written into the
  /// middle of raw file bytes would corrupt the stream. The peer stays
  /// satisfied because the file bytes themselves are traffic.
  Future<void> sendBinary(
    Stream<List<int>> data, {
    required void Function(int byteCount) onProgress,
  }) async {
    _writingBinary = true;
    try {
      int unflushed = 0;
      await for (final List<int> chunk in data) {
        if (_disposed) throw HozaError.lost;
        _socket.add(chunk);
        onProgress(chunk.length);
        unflushed += chunk.length;
        if (unflushed < _flushThreshold) continue;
        unflushed = 0;
        // Waits for the socket buffer to drain, which is what keeps a fast
        // disk from queueing an entire file ahead of a slow network.
        await _socket.flush();
      }
      await _socket.flush();
    } finally {
      _writingBinary = false;
    }
  }

  /// Stops reading from the socket. Used while a disk write drains, so
  /// incoming data cannot outrun storage.
  void pauseInput() {
    if (_inputPaused || _disposed) return;
    _inputPaused = true;
    _subscription?.pause();
  }

  void resumeInput() {
    if (!_inputPaused || _disposed) return;
    _inputPaused = false;
    _subscription?.resume();
  }

  /// Ends the session. [error] null means this was expected.
  Future<void> close([HozaError? error]) async {
    if (_disposed) return;
    if (error == null) send(ControlMessage.bye);
    _finish(error);
  }

  void _onData(List<int> chunk) {
    _lastInbound = DateTime.now();
    _reader.add(chunk, onLine: _onLine);
    if (!_reader.hasOverflowed) return;
    Log.warn(_tag, 'Peer sent an oversized line; dropping connection');
    _finish(HozaError.lost);
  }

  void _onLine(String line) {
    final ControlMessage? message = ControlMessage.decode(line);
    if (message == null) return;

    switch (message.type) {
      case ControlType.ping:
        send(ControlMessage.pong);
      case ControlType.pong:
        break;
      case ControlType.bye:
        Log.info(_tag, 'Peer closed the session');
        _finish(null);
      case ControlType.unknown:
        // A newer build may send things this one does not know. Ignoring is
        // correct; the version check already rejected true mismatches.
        break;
      default:
        if (!_messages.isClosed) _messages.add(message);
    }
  }

  void _onHeartbeat() {
    if (DateTime.now().difference(_lastInbound) > _livenessTimeout) {
      Log.warn(_tag, 'No response from ${remote.name}; connection lost');
      _finish(HozaError.lost);
      return;
    }
    if (_writingBinary) return;
    send(ControlMessage.ping);
  }

  void _onSocketError(Object error) {
    Log.warn(_tag, 'Socket error: $error');
    _finish(HozaError.from(error));
  }

  void _onSocketDone() => _finish(_disposed ? null : HozaError.lost);

  void _finish(HozaError? error) {
    if (_disposed) return;
    _disposed = true;
    _heartbeat?.cancel();
    _heartbeat = null;
    if (error != null) Log.info(_tag, 'Session ended: ${error.kind.name}');
    unawaited(_flushAndDestroy());
    if (!_messages.isClosed) _messages.close();
    if (!_closed.isCompleted) _closed.complete(error);
  }

  /// Gives a queued `bye` a chance to reach the wire before the socket is torn
  /// down, so the peer can drop the session at once instead of waiting for the
  /// liveness timeout.
  Future<void> _flushAndDestroy() async {
    try {
      await _socket.flush();
    } catch (_) {
      // Tearing down anyway; nothing useful to do with a failure here.
    }
    _socket.destroy();
  }
}
