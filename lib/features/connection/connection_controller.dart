import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/hoza_error.dart';
import '../../core/models/hoza_device.dart';
import '../../core/services/device_identity.dart';
import '../../core/utils/log.dart';
import '../../network/connection/connection_client.dart';
import '../../network/connection/connection_server.dart';
import '../../network/connection/hoza_session.dart';
import '../../network/protocol/control_message.dart';
import '../settings/settings_controller.dart';

/// Where a connection attempt has got to.
enum SessionState {
  idle,
  connecting,

  /// Waiting for the other user to press Accept.
  awaitingApproval,

  connected,

  /// They pressed Reject, or did not answer.
  rejected,

  /// Something went wrong. [ConnectionController.error] says what.
  failed;

  /// True while a session exists or is being built, so a second attempt is
  /// refused rather than trampling the first.
  bool get isBusy =>
      this == connecting || this == awaitingApproval || this == connected;
}

/// The UI-facing half of connecting.
///
/// Runs the server that answers other devices, and drives the client side when
/// this user picks someone to connect to.
class ConnectionController extends ChangeNotifier {
  ConnectionController(this._settings) {
    _server = ConnectionServer(
      selfDevice: _selfDevice,
      isBusy: () => _session != null,
    );
    _requestSub = _server.requests.listen(_onIncoming);
  }

  /// How long to wait for the other user to answer before giving up. Slightly
  /// longer than the receiver's own window, so their timeout lands first and
  /// they get the clearer message.
  static const Duration _approvalWindow = Duration(seconds: 50);

  final SettingsController _settings;
  late final ConnectionServer _server;
  late final StreamSubscription<IncomingRequest> _requestSub;

  StreamSubscription<ControlMessage>? _messageSub;
  Timer? _approvalTimer;

  HozaSession? _session;
  SessionState _state = SessionState.idle;
  HozaDevice? _peer;
  String? _code;
  HozaError? _error;
  IncomingRequest? _incoming;
  String? _serverError;

  SessionState get state => _state;

  /// The device at the other end of the current or last attempt.
  HozaDevice? get peer => _peer;

  /// The six digit code shown on both screens.
  String? get code => _code;

  HozaError? get error => _error;

  /// A pending request from another device, if the user has not answered yet.
  IncomingRequest? get incoming => _incoming;

  /// Set when the app could not listen for connections at all.
  String? get serverError => _serverError;

  bool get isConnected => _state == SessionState.connected;

  /// The live connection, for the transfer layer to send and receive over.
  /// Null unless [isConnected].
  HozaSession? get session => _state == SessionState.connected ? _session : null;

  /// Starts answering connections. Safe to call more than once.
  Future<void> start() async {
    if (_server.isRunning) return;
    if (await _server.start()) {
      _serverError = null;
    } else {
      _serverError =
          'HozaSend cannot receive connections right now. Another app may be '
          'using the port, or a firewall is blocking it.';
    }
    notifyListeners();
  }

  /// Connects to a device the user picked from the nearby list.
  Future<void> connectTo(HozaDevice device) async {
    if (_state.isBusy) return;

    _error = null;
    _peer = device;
    _code = SessionCode.generate();
    _state = SessionState.connecting;
    notifyListeners();

    try {
      final HozaSession session = await ConnectionClient.connect(
        target: device,
        self: _selfDevice(),
        code: _code!,
      );
      _bind(session);
      _state = SessionState.awaitingApproval;
      _approvalTimer = Timer(_approvalWindow, () {
        if (_state == SessionState.awaitingApproval) _fail(HozaError.noAnswer);
      });
      notifyListeners();
    } catch (error) {
      _fail(HozaError.from(error));
    }
  }

  void acceptIncoming() {
    final IncomingRequest? request = _incoming;
    if (request == null) return;
    _incoming = null;
    _accept(request);
  }

  void rejectIncoming() {
    final IncomingRequest? request = _incoming;
    if (request == null) return;
    _incoming = null;
    request.reject();
    notifyListeners();
  }

  /// Ends the session, whether it is connected or still being set up.
  void disconnect() {
    _approvalTimer?.cancel();
    final HozaSession? session = _session;
    _session = null;
    unawaited(session?.close());
    _reset();
  }

  /// Clears a finished attempt so the sheet can close and the next one can
  /// start. Does nothing while a session is live.
  void dismiss() {
    if (_state.isBusy) return;
    _reset();
  }

  @override
  void dispose() {
    _approvalTimer?.cancel();
    _messageSub?.cancel();
    _requestSub.cancel();
    unawaited(_session?.close());
    _server.dispose();
    super.dispose();
  }

  void _bind(HozaSession session) {
    _session = session;
    _messageSub?.cancel();
    _messageSub = session.messages.listen(_onMessage);
    session.closed.then(_onSessionClosed);
  }

  void _onMessage(ControlMessage message) {
    final HozaSession? session = _session;
    if (session == null) return;

    switch (message.type) {
      case ControlType.welcome:
        // The receiver's real name, which discovery may not have had.
        final HozaDevice? device = message.deviceFrom(session.remote.address);
        if (device != null) {
          session.remote = device;
          _peer = device;
          notifyListeners();
        }

      case ControlType.accept:
        _approvalTimer?.cancel();
        _state = SessionState.connected;
        _peer = session.remote;
        Log.info('Connection', 'Connected to ${session.remote.name}');
        notifyListeners();

      case ControlType.reject:
        _approvalTimer?.cancel();
        _state = SessionState.rejected;
        _error = message.reason == 'timeout'
            ? HozaError.noAnswer
            : HozaError.declined;
        notifyListeners();

      case ControlType.error:
        _fail(switch (message.errorCode) {
          'version' => HozaError.incompatible,
          'busy' => HozaError.deviceBusy,
          _ => HozaError.unreachable,
        });

      default:
        // Transfer traffic on this session belongs to TransferController,
        // which listens to the same stream.
        break;
    }
  }

  void _onIncoming(IncomingRequest request) {
    if (_settings.settings.autoAccept) {
      Log.info('Connection', 'Auto-accepting ${request.device.name}');
      _accept(request);
      return;
    }
    _incoming = request;
    request.onResolved = () {
      if (!identical(_incoming, request)) return;
      _incoming = null;
      notifyListeners();
    };
    notifyListeners();
  }

  void _accept(IncomingRequest request) {
    request.accept();
    _bind(request.session);
    _peer = request.device;
    _code = request.code;
    _error = null;
    _state = SessionState.connected;
    notifyListeners();
  }

  void _onSessionClosed(HozaError? error) {
    _messageSub?.cancel();
    _messageSub = null;
    _session = null;
    _approvalTimer?.cancel();

    // A close during rejected or failed is expected - the state is already
    // right and overwriting it would lose the reason the user needs to see.
    if (!_state.isBusy) return;

    if (error == null) {
      _reset();
    } else {
      _error = error;
      _state = SessionState.failed;
      notifyListeners();
    }
  }

  void _fail(HozaError error) {
    _approvalTimer?.cancel();
    _error = error;
    _state = SessionState.failed;
    final HozaSession? session = _session;
    _session = null;
    unawaited(session?.close(error));
    notifyListeners();
  }

  void _reset() {
    _state = SessionState.idle;
    _peer = null;
    _code = null;
    _error = null;
    notifyListeners();
  }

  HozaDevice _selfDevice() => HozaDevice(
        id: _settings.deviceId,
        name: _settings.deviceName.isEmpty
            ? AppConstants.appName
            : _settings.deviceName,
        platform: DeviceIdentity.platform,
        address: '',
        port: AppConstants.transferPort,
        appVersion: AppConstants.appVersion,
        lastSeen: DateTime.now(),
      );
}
