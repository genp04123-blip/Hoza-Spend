import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/hoza_error.dart';
import '../../core/models/hoza_device.dart';
import '../../core/services/device_identity.dart';
import '../../core/services/foreground_service.dart';
import '../../core/services/wifi_lock_service.dart';
import '../../core/utils/ids.dart';
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

  /// Something went wrong. [PeerLink.error] says what.
  failed;

  /// True while this particular link exists or is being built.
  bool get isBusy =>
      this == connecting || this == awaitingApproval || this == connected;
}

/// One device this app is talking to, or trying to.
///
/// There is one of these per peer. Everything that used to be a single field
/// on the controller - the session, the state, the code, the error - lives
/// here instead, which is the whole of what made connecting to a second device
/// impossible before.
class PeerLink {
  PeerLink({
    required this.device,
    required this.code,
    required this.state,
    this.session,
  });

  /// Stable for the life of the link. Deliberately not the device id: a
  /// connect-by-IP link starts life with a made-up id and is handed the real
  /// one a moment later, and the UI must not lose the row it was watching.
  final String id = Ids.next('link-');

  /// The device at the other end. Replaced by the real identity once the
  /// welcome or hello arrives.
  HozaDevice device;

  HozaSession? session;
  SessionState state;

  /// The six digit code shown on both screens.
  String code;

  HozaError? error;

  StreamSubscription<ControlMessage>? messages;
  Timer? approvalTimer;

  bool get isConnected => state == SessionState.connected;
  bool get isBusy => state.isBusy;

  /// True when this link is finished with and only still exists so the user
  /// can read why.
  bool get isFinished => !state.isBusy;

  String get name => device.name;

  void cancelTimers() {
    approvalTimer?.cancel();
    approvalTimer = null;
  }

  Future<void> detach([HozaError? error]) async {
    cancelTimers();
    unawaited(messages?.cancel());
    messages = null;
    final HozaSession? live = session;
    session = null;
    await live?.close(error);
  }
}

/// The UI-facing half of connecting.
///
/// Runs the server that answers other devices, and drives the client side when
/// this user picks someone to connect to. Holds up to
/// [AppConstants.maxSessions] links at once, each independent of the others: a
/// transfer with one device neither blocks nor ends a session with another.
///
/// One of them is the *active* link. That is only a UI notion - it is the
/// device the send screen is pointed at, and the one the single-peer getters
/// below answer for - and switching it changes nothing on the wire.
class ConnectionController extends ChangeNotifier with WidgetsBindingObserver {
  ConnectionController(this._settings) {
    _server = ConnectionServer(
      selfDevice: _selfDevice,
      canAccept: _canAccept,
    );
    _requestSub = _server.requests.listen(_onIncoming);
    WidgetsBinding.instance.addObserver(this);
  }

  /// How long to wait for the other user to answer before giving up. Slightly
  /// longer than the receiver's own window, so their timeout lands first and
  /// they get the clearer message.
  static const Duration _approvalWindow = Duration(seconds: 50);

  final SettingsController _settings;
  late final ConnectionServer _server;
  late final StreamSubscription<IncomingRequest> _requestSub;

  final List<PeerLink> _links = <PeerLink>[];
  final List<IncomingRequest> _requests = <IncomingRequest>[];

  String? _activeId;
  String? _serverError;
  bool _linkHeld = false;

  /// Every link, live or finished, in the order they were made.
  List<PeerLink> get links => List<PeerLink>.unmodifiable(_links);

  /// The links with a session up, which is what the rest of the app cares
  /// about almost everywhere.
  List<PeerLink> get connectedLinks =>
      _links.where((PeerLink link) => link.isConnected).toList(growable: false);

  int get connectedCount => connectedLinks.length;

  /// True while another device could still be added.
  bool get hasRoom => freeSlots > 0;

  /// How many slots are left, for the screens that say so out loud.
  ///
  /// Requests still sitting on this user's screen count against it. They are
  /// about to become sessions, and letting the user dial out into a slot
  /// someone is already queued for is how both ends end up refused.
  int get freeSlots {
    final int free =
        AppConstants.maxSessions - _liveCount - _server.pendingCount;
    return free < 0 ? 0 : free;
  }

  /// Links that are up or on their way up. A failed link still sits in [_links]
  /// so its error can be read, but it is not holding a slot.
  int get _liveCount => _links.where((PeerLink link) => link.isBusy).length;

  /// The link the send screen is pointed at.
  PeerLink? get active {
    for (final PeerLink link in _links) {
      if (link.id == _activeId) return link;
    }
    // Whatever is most recently usable, so the getters below are never stale
    // just because the active link was hung up.
    for (final PeerLink link in _links.reversed) {
      if (link.isConnected) return link;
    }
    return _links.isEmpty ? null : _links.last;
  }

  /// Points the send screen at [link]. Purely local; nothing is sent.
  void setActive(PeerLink link) {
    if (_activeId == link.id) return;
    _activeId = link.id;
    notifyListeners();
  }

  /// The link for [device], if this app holds one.
  PeerLink? linkFor(HozaDevice device) {
    for (final PeerLink link in _links) {
      if (link.isBusy && link.device.isSameAs(device)) return link;
    }
    return null;
  }

  // --- Single-peer view, kept so every screen that only cares about "the"
  // --- device keeps working. Each one answers for the active link.

  SessionState get state => active?.state ?? SessionState.idle;

  /// The device at the other end of the active link.
  HozaDevice? get peer => active?.device;

  /// The six digit code shown on both screens.
  String? get code => active?.code;

  HozaError? get error => active?.error;

  bool get isConnected => active?.isConnected ?? false;

  /// The live connection, for the transfer layer to send over. Null unless the
  /// active link is connected.
  HozaSession? get session {
    final PeerLink? link = active;
    return link != null && link.isConnected ? link.session : null;
  }

  /// A pending request from another device, if the user has not answered yet.
  ///
  /// They are answered one at a time, oldest first: two prompts stacked on top
  /// of each other is not a decision anyone can make.
  IncomingRequest? get incoming {
    _requests.removeWhere((IncomingRequest request) => request.isResolved);
    return _requests.isEmpty ? null : _requests.first;
  }

  /// Set when the app could not listen for connections at all.
  String? get serverError => _serverError;

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

  /// Binding the port can fail at launch for reasons that clear on their own -
  /// Wi-Fi not up yet, or the port still held by a previous run that Android
  /// has not finished killing. Coming back to the app is the natural moment to
  /// try again, and it costs one call.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_server.isRunning) unawaited(start());
  }

  /// Connects to a device the user picked from the nearby list.
  ///
  /// Already connected to it? Then this just points the send screen at it. The
  /// old build refused silently here whenever *any* session existed, which is
  /// what made a second device impossible and a stale first one fatal.
  Future<void> connectTo(HozaDevice device) async {
    final PeerLink? existing = linkFor(device);
    if (existing != null) {
      setActive(existing);
      return;
    }

    // Finished links are only kept so their error can be read. Once the user
    // dials again, the one for this device has served its purpose.
    _links.removeWhere(
      (PeerLink link) => link.isFinished && link.device.isSameAs(device),
    );

    if (!hasRoom) {
      Log.info('Connection', 'Refusing ${device.name}: all slots in use');
      final PeerLink full = PeerLink(
        device: device,
        code: '',
        state: SessionState.failed,
      )..error = HozaError.atCapacity;
      _links.add(full);
      _activeId = full.id;
      notifyListeners();
      return;
    }

    final PeerLink link = PeerLink(
      device: device,
      code: SessionCode.generate(),
      state: SessionState.connecting,
    );
    _links.add(link);
    _activeId = link.id;
    notifyListeners();

    try {
      final HozaSession session = await ConnectionClient.connect(
        target: device,
        self: _selfDevice(),
        code: link.code,
      );
      // The user may have cancelled while the socket was being opened.
      if (!_links.contains(link)) {
        unawaited(session.close());
        return;
      }
      _bind(link, session);
      link.state = SessionState.awaitingApproval;
      link.approvalTimer = Timer(_approvalWindow, () {
        if (link.state == SessionState.awaitingApproval) {
          _fail(link, HozaError.noAnswer);
        }
      });
      notifyListeners();
    } catch (error) {
      _fail(link, HozaError.from(error));
    }
  }

  void acceptIncoming() {
    final IncomingRequest? request = incoming;
    if (request == null) return;
    _requests.remove(request);
    _accept(request);
  }

  void rejectIncoming() {
    final IncomingRequest? request = incoming;
    if (request == null) return;
    _requests.remove(request);
    request.reject();
    notifyListeners();
  }

  /// Ends the active session, whether it is connected or still being set up.
  void disconnect() {
    final PeerLink? link = active;
    if (link != null) disconnectLink(link);
  }

  /// Ends one session and leaves every other one alone.
  void disconnectLink(PeerLink link) {
    // Marked before it is detached, so the close that follows reads as the
    // expected end of a link nobody is waiting on rather than as a session
    // dropping out from under a live screen.
    link.state = SessionState.idle;
    unawaited(link.detach());
    _links.remove(link);
    if (_activeId == link.id) _activeId = null;
    _releaseLinkIfIdle();
    _refreshSessionNotice();
    notifyListeners();
  }

  /// Clears finished attempts so their sheets can close and the next one can
  /// start. Live links are left alone.
  void dismiss() {
    final int before = _links.length;
    _links.removeWhere((PeerLink link) => link.isFinished);
    if (_links.length == before) return;
    if (!_links.any((PeerLink link) => link.id == _activeId)) _activeId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final PeerLink link in _links) {
      unawaited(link.detach());
    }
    _links.clear();
    _releaseLink();
    _requestSub.cancel();
    _server.dispose();
    super.dispose();
  }

  /// Whether an incoming request can be taken. Consulted by the server before
  /// a prompt is ever raised.
  bool _canAccept(HozaDevice device, int pending) {
    // A device that is already linked here is reconnecting - its old session
    // is stale and will be replaced - so it is not asking for a new slot.
    if (linkFor(device) != null) return true;
    return _liveCount + pending < AppConstants.maxSessions;
  }

  void _bind(PeerLink link, HozaSession session) {
    link.session = session;
    unawaited(link.messages?.cancel());
    link.messages = session.messages.listen(
      (ControlMessage message) => _onMessage(link, message),
    );
    session.closed.then((HozaError? error) => _onSessionClosed(link, error));
    _holdLink();
  }

  /// Keeps the Wi-Fi radio at full power - and the process itself running -
  /// while at least one session exists.
  ///
  /// Three separate things, each covering a different way a transfer dies when
  /// the user is not looking at it. The multicast lock discovery holds stops
  /// broadcast packets being filtered, and does nothing for throughput. The
  /// link lock keeps the radio out of its power-saving duty cycle, without
  /// which a long transfer with the screen off is throttled to a crawl and
  /// eventually trips the liveness timeout. And the foreground service keeps
  /// Android from freezing the process outright a few minutes after the app
  /// leaves the screen, which no amount of radio wakefulness helps with.
  void _holdLink() {
    if (_linkHeld) return;
    _linkHeld = true;
    unawaited(WifiLockService.acquireLink());
    _showSessionNotice();
  }

  void _releaseLink() {
    if (!_linkHeld) return;
    _linkHeld = false;
    unawaited(WifiLockService.releaseLink());
    unawaited(ForegroundService.hide());
  }

  /// Drops the locks only once the last session has gone. With several peers
  /// the whole point is that one of them ending is not the end of anything.
  void _releaseLinkIfIdle() {
    if (_links.any((PeerLink link) => link.session != null)) return;
    _releaseLink();
  }

  /// The line the session notification carries while nothing is moving.
  ///
  /// Replaced by [updateSessionProgress] as soon as a transfer starts, and
  /// restored by it when one finishes: the notification lives for as long as
  /// any session does, not just for the transfer inside it.
  void _showSessionNotice() {
    if (!_linkHeld) return;
    unawaited(
      ForegroundService.show(
        title: _sessionTitle(),
        text: 'Keeping the connection open.',
      ),
    );
  }

  /// Only worth redrawing when a session actually exists; otherwise the
  /// notification is on its way down anyway.
  void _refreshSessionNotice() {
    if (_links.every((PeerLink link) => link.session == null)) return;
    _showSessionNotice();
  }

  String _sessionTitle() {
    final List<PeerLink> live =
        _links.where((PeerLink link) => link.session != null).toList();
    if (live.isEmpty) return 'HozaSend session';
    if (live.length == 1) return 'Connected to ${live.first.name}';
    return 'Connected to ${live.length} devices';
  }

  /// Lets the transfer layer put what is actually happening on the
  /// notification, without it needing to know anything about locks or
  /// services. Passing null puts the idle line back.
  void updateSessionProgress({String? text, int? percent}) {
    if (!_linkHeld) return;
    if (text == null) {
      _showSessionNotice();
      return;
    }
    unawaited(
      ForegroundService.show(
        title: _sessionTitle(),
        text: text,
        progress: percent,
      ),
    );
  }

  void _onMessage(PeerLink link, ControlMessage message) {
    final HozaSession? session = link.session;
    if (session == null) return;

    switch (message.type) {
      case ControlType.welcome:
        // The receiver's real name, which discovery may not have had.
        final HozaDevice? device = message.deviceFrom(session.remote.address);
        if (device != null) {
          session.remote = device;
          link.device = device;
          // The notification went up before the name was known, addressed to
          // nobody in particular. Now it can say who.
          _refreshSessionNotice();
          notifyListeners();
        }

      case ControlType.accept:
        link.cancelTimers();
        link.state = SessionState.connected;
        link.device = session.remote;
        _activeId ??= link.id;
        _refreshSessionNotice();
        Log.info('Connection', 'Connected to ${session.remote.name}');
        notifyListeners();

      case ControlType.reject:
        link.cancelTimers();
        link.state = SessionState.rejected;
        link.error = message.reason == 'timeout'
            ? HozaError.noAnswer
            : HozaError.declined;
        notifyListeners();

      case ControlType.error:
        _fail(
          link,
          switch (message.errorCode) {
            'version' => HozaError.incompatible,
            'busy' => HozaError.deviceBusy,
            _ => HozaError.unreachable,
          },
        );

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
    _requests
      ..removeWhere((IncomingRequest queued) => queued.isResolved)
      ..add(request);
    request.onResolved = () {
      if (!_requests.remove(request)) return;
      notifyListeners();
    };
    notifyListeners();
  }

  void _accept(IncomingRequest request) {
    // A device reconnecting replaces whatever this side still thought it had.
    // Without this, the old half-dead session sits there holding a slot and
    // the next device to knock is told this one is busy.
    final PeerLink? stale = linkFor(request.device);
    if (stale != null) {
      Log.info('Connection', '${request.device.name} reconnected');
      unawaited(stale.detach());
      _links.remove(stale);
      if (_activeId == stale.id) _activeId = null;
    }
    _links.removeWhere(
      (PeerLink link) =>
          link.isFinished && link.device.isSameAs(request.device),
    );

    request.accept();

    final PeerLink link = PeerLink(
      device: request.device,
      code: request.code,
      state: SessionState.connected,
    );
    _links.add(link);
    _activeId = link.id;
    _bind(link, request.session);
    // After the link is in the list, so the notification can count it.
    _refreshSessionNotice();
    notifyListeners();
  }

  void _onSessionClosed(PeerLink link, HozaError? error) {
    unawaited(link.messages?.cancel());
    link.messages = null;
    link.session = null;
    link.cancelTimers();
    _releaseLinkIfIdle();

    // A close during rejected or failed is expected - the state is already
    // right and overwriting it would lose the reason the user needs to see.
    if (link.isBusy) {
      if (error == null) {
        // An orderly goodbye. Nothing to report, so the row simply goes.
        _links.remove(link);
        if (_activeId == link.id) _activeId = null;
      } else {
        link.error = error;
        link.state = SessionState.failed;
      }
    }

    _refreshSessionNotice();
    notifyListeners();
  }

  void _fail(PeerLink link, HozaError error) {
    link.cancelTimers();
    link.error = error;
    link.state = SessionState.failed;
    unawaited(link.detach(error));
    _releaseLinkIfIdle();
    _refreshSessionNotice();
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
