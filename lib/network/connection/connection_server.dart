import 'dart:async';
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/errors/hoza_error.dart';
import '../../core/models/hoza_device.dart';
import '../../core/utils/log.dart';
import '../discovery/discovery_service.dart' show SelfDeviceProvider;
import '../protocol/control_message.dart';
import 'hoza_session.dart';

/// A connection another device has asked for, waiting on this user's answer.
///
/// Resolves exactly once, whether by the user, by the timeout, or because the
/// peer gave up and closed first.
class IncomingRequest {
  IncomingRequest({required this.session, required this.device}) {
    _timeout = Timer(responseWindow, () => reject('timeout'));
    // If the initiator walks away, drop the prompt rather than leaving a dead
    // card on screen.
    session.closed.then((_) => _resolve());
  }

  /// How long the prompt stays up before declining on the user's behalf.
  /// Long enough to walk back to the other device, short enough that a
  /// forgotten request does not block the next one.
  static const Duration responseWindow = Duration(seconds: 45);

  final HozaSession session;
  final HozaDevice device;

  String get code => session.code;

  Timer? _timeout;
  bool _resolved = false;
  bool get isResolved => _resolved;

  final Completer<void> _done = Completer<void>();

  /// Completes when this request stops being actionable, for any reason.
  /// Separate from [onResolved] because the server and the controller both
  /// need to know, and a single callback slot means whoever assigns second
  /// silently replaces the first.
  Future<void> get resolved => _done.future;

  /// Fired when this request stops being actionable, for any reason.
  void Function()? onResolved;

  void accept() {
    if (_resolved) return;
    _resolve();
    Log.info('Connection', 'Accepted ${device.name}');
    session.send(ControlMessage.accept);
  }

  void reject([String reason = 'declined']) {
    if (_resolved) return;
    _resolve();
    Log.info('Connection', 'Rejected ${device.name} ($reason)');
    session.send(ControlMessage.reject(reason));
    unawaited(session.close());
  }

  void _resolve() {
    if (_resolved) return;
    _resolved = true;
    _timeout?.cancel();
    _timeout = null;
    if (!_done.isCompleted) _done.complete();
    onResolved?.call();
  }
}

/// Listens for incoming connections and turns valid ones into an
/// [IncomingRequest] for the user to answer.
///
/// Every device runs one of these. There is no "sender" and "receiver" build:
/// the same app both offers and accepts.
class ConnectionServer {
  ConnectionServer({required this.selfDevice, required this.isBusy});

  final SelfDeviceProvider selfDevice;

  /// Consulted before a request is raised. A device already in a session
  /// refuses politely instead of dropping the user into two at once.
  final bool Function() isBusy;

  static const String _tag = 'Connection';

  ServerSocket? _server;

  /// The request already on this user's screen, if any.
  ///
  /// Tracked here rather than only in the controller because the controller
  /// learns about a request one microtask late, through a broadcast stream.
  /// Two devices connecting in the same instant would both slip through that
  /// gap, and the first user's prompt would be replaced by the second without
  /// either peer being told - the first would simply hang until it timed out.
  IncomingRequest? _pending;

  final StreamController<IncomingRequest> _requests =
      StreamController<IncomingRequest>.broadcast();

  Stream<IncomingRequest> get requests => _requests.stream;
  bool get isRunning => _server != null;

  /// True while this device cannot take another connection: it is already in
  /// one, or it is asking the user about one.
  bool get _isEngaged {
    final IncomingRequest? pending = _pending;
    if (pending != null && !pending.isResolved) return true;
    return isBusy();
  }

  /// False if the port could not be opened; the caller turns that into a
  /// message the user can act on.
  Future<bool> start() async {
    if (_server != null) return true;
    try {
      final ServerSocket server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        AppConstants.transferPort,
      );
      server.listen(
        _onSocket,
        onError: (Object error) => Log.warn(_tag, 'Accept failed: $error'),
      );
      _server = server;
      Log.info(_tag, 'Accepting connections on ${AppConstants.transferPort}');
      return true;
    } on SocketException catch (error) {
      Log.warn(
        _tag,
        'Could not bind TCP ${AppConstants.transferPort}: '
        '${error.osError?.message ?? error.message}',
      );
      return false;
    }
  }

  Future<void> stop() async {
    final ServerSocket? server = _server;
    _server = null;
    // A request nobody can answer any more is declined rather than left to
    // time out, so the other device is told at once instead of in 45 seconds.
    _pending?.reject('unavailable');
    _pending = null;
    await server?.close();
  }

  void dispose() {
    unawaited(stop());
    _requests.close();
  }

  void _onSocket(Socket socket) {
    // Control messages are tiny and latency matters more than packing them.
    socket.setOption(SocketOption.tcpNoDelay, true);
    final String address = socket.remoteAddress.address;

    // The peer's real identity arrives in its hello. Until then it is only an
    // address, which is all we can honestly claim to know.
    final HozaSession session = HozaSession(
      socket,
      remote: HozaDevice(
        id: '',
        name: 'Unknown device',
        platform: DevicePlatform.unknown,
        address: address,
        port: AppConstants.transferPort,
        appVersion: '',
        lastSeen: DateTime.now(),
      ),
      code: '',
      isInitiator: false,
    );

    bool introduced = false;

    // A connection that never introduces itself is dropped rather than left to
    // hold the port open.
    final Timer handshake = Timer(AppConstants.connectionTimeout, () {
      if (introduced || !session.isOpen) return;
      Log.warn(_tag, 'No hello from $address; closing');
      unawaited(session.close(HozaError.noAnswer));
    });
    session.closed.then((_) => handshake.cancel());

    // Deliberately not cancelled after the hello: the stream is broadcast, and
    // cancelling here would leave a window where a message could be dropped
    // before the controller attaches its own listener.
    session.messages.listen((ControlMessage message) {
      if (introduced || message.type != ControlType.hello) return;
      introduced = true;
      handshake.cancel();
      _onHello(session, message, address);
    });
  }

  void _onHello(HozaSession session, ControlMessage message, String address) {
    if (message.protocolVersion != AppConstants.protocolVersion) {
      Log.warn(_tag, 'Version mismatch from $address');
      session.send(
        ControlMessage.error('version', 'Incompatible protocol version'),
      );
      unawaited(session.close(HozaError.incompatible));
      return;
    }

    final HozaDevice? device = message.deviceFrom(address);
    if (device == null) {
      unawaited(session.close(HozaError.lost));
      return;
    }

    if (_isEngaged) {
      Log.info(_tag, 'Refusing ${device.name}: already engaged');
      session.send(ControlMessage.error('busy', 'Already in a transfer'));
      unawaited(session.close(HozaError.deviceBusy));
      return;
    }

    session.remote = device;
    session.code = message.sessionCode ?? '';

    // Tells the initiator the request landed, so its screen can move from
    // "connecting" to "waiting for them to accept".
    session.send(ControlMessage.welcome(selfDevice()));

    Log.info(_tag, 'Connection request from ${device.name} ($address)');
    if (_requests.isClosed) {
      unawaited(session.close(HozaError.lost));
      return;
    }

    final IncomingRequest request =
        IncomingRequest(session: session, device: device);
    // Claimed synchronously, before the broadcast stream has told anyone, so
    // a second connection arriving in the same instant is refused rather than
    // quietly taking the first one's place.
    _pending = request;
    request.resolved.then((_) {
      if (identical(_pending, request)) _pending = null;
    });
    _requests.add(request);
  }
}
