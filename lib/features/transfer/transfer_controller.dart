import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/hoza_error.dart';
import '../../core/models/transfer.dart';
import '../../core/services/notification_service.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/log.dart';
import '../../network/connection/hoza_session.dart';
import '../../network/transfer/transfer_receiver.dart';
import '../../network/transfer/transfer_sender.dart';
import '../connection/connection_controller.dart';
import '../history/history_controller.dart';
import '../settings/settings_controller.dart';

/// An incoming transfer waiting on this user's answer.
class PendingOffer {
  PendingOffer(this._decision, {required this.files, required this.deviceName});

  final List<TransferFile> files;
  final String deviceName;
  final Completer<bool> _decision;

  int get totalBytes =>
      files.fold<int>(0, (int sum, TransferFile f) => sum + f.size);

  bool get isResolved => _decision.isCompleted;

  void accept() {
    if (_decision.isCompleted) return;
    _decision.complete(true);
  }

  void reject() {
    if (_decision.isCompleted) return;
    _decision.complete(false);
  }
}

/// One connected device, with the receiver listening on its session.
class _BoundPeer {
  _BoundPeer({
    required this.link,
    required this.session,
    required this.receiver,
  });

  final PeerLink link;
  final HozaSession session;
  final TransferReceiver receiver;
}

/// The UI-facing half of transferring.
///
/// Holds one transfer at a time, in either direction, but listens on *every*
/// connected device: files can start arriving from any of them without this
/// user pressing anything, and a receiver attached to only one peer would
/// leave the others unable to send at all.
///
/// One at a time is deliberate. Two transfers sharing a phone's disk and radio
/// finish later than the same two run back to back, and a progress screen that
/// has to describe both is a screen nobody can read. A second offer arriving
/// mid-transfer is declined politely rather than queued.
class TransferController extends ChangeNotifier {
  TransferController(this._connection, this._settings, this._history) {
    _connection.addListener(_onConnectionChanged);
    _onConnectionChanged();
  }

  /// How long the incoming prompt stays up before declining on the user's
  /// behalf. Matches the connection prompt, so the two feel the same.
  static const Duration _promptWindow = Duration(seconds: 45);

  final ConnectionController _connection;
  final SettingsController _settings;
  final HistoryController _history;

  /// Every connected device, keyed by link id.
  final Map<String, _BoundPeer> _peers = <String, _BoundPeer>{};

  TransferSender? _sender;

  /// The peer whose transfer is on screen, so Cancel knows what to stop and a
  /// dropped session knows whether it took a live transfer down with it.
  String? _activePeerId;

  PendingOffer? _offer;

  /// Which peer the pending offer came from, so a session dropping while the
  /// prompt is up clears that prompt and no other.
  String? _offerPeerId;

  Timer? _promptTimer;

  TransferDirection? _direction;
  List<TransferFile> _files = const <TransferFile>[];
  TransferProgress _progress = TransferProgress.zero;
  TransferStatus _status = TransferStatus.pending;
  HozaError? _error;
  String? _deviceName;
  DateTime? _startedAt;

  /// Kept so a failed send can be retried without picking the files again.
  List<TransferFile> _lastSent = const <TransferFile>[];

  /// Null when nothing has been transferred this session.
  TransferDirection? get direction => _direction;

  List<TransferFile> get files => _files;
  TransferProgress get progress => _progress;
  TransferStatus get status => _status;
  HozaError? get error => _error;
  String? get deviceName => _deviceName;

  /// An incoming transfer the user has not answered yet.
  PendingOffer? get incomingOffer => _offer;

  bool get hasTransfer => _direction != null;
  bool get isActive => hasTransfer && !_status.isFinished;
  bool get isSending => _direction == TransferDirection.send;

  /// True when the last send failed and the same files could go again. Needs
  /// the session to still be up; reconnecting first is a different action.
  bool get canRetry =>
      isSending &&
      _status.isFinished &&
      _status != TransferStatus.completed &&
      _lastSent.isNotEmpty &&
      _connection.isConnected;

  /// Sends [files] to the device the send screen is pointed at. Returns when
  /// the transfer has finished, one way or another.
  Future<void> send(List<TransferFile> files) async {
    final PeerLink? link = _connection.active;
    final HozaSession? session = _connection.session;
    if (link == null || session == null || files.isEmpty || isActive) return;

    _lastSent = List<TransferFile>.unmodifiable(files);
    _direction = TransferDirection.send;
    _files = _lastSent;
    _deviceName = link.device.name;
    _activePeerId = link.id;
    _startedAt = DateTime.now();
    _error = null;
    _status = TransferStatus.awaitingApproval;
    _progress = TransferProgress(
      bytesTransferred: 0,
      totalBytes: files.fold<int>(0, (int sum, TransferFile f) => sum + f.size),
      bytesPerSecond: 0,
      filesTotal: files.length,
    );
    notifyListeners();

    final TransferSender sender = TransferSender(
      session,
      files: files,
      onProgress: _onProgress,
    );
    _sender = sender;
    try {
      await sender.run();
      _status = TransferStatus.completed;
    } catch (error) {
      _applyFailure(HozaError.from(error));
    } finally {
      _sender = null;
      _activePeerId = null;
      _record();
      notifyListeners();
    }
  }

  /// Sends the same files again after a failure.
  Future<void> retry() async {
    if (!canRetry) return;
    final List<TransferFile> files = _lastSent;
    _status = TransferStatus.pending;
    _direction = null;
    await send(files);
  }

  /// Stops the transfer in flight, whichever direction it is going.
  void cancel() {
    if (!isActive) return;
    Log.info('Transfer', 'Cancelled by this user');
    _sender?.cancel();
    final String? id = _activePeerId;
    if (id != null) _peers[id]?.receiver.cancel();
  }

  /// Clears a finished transfer so the screen can close.
  void reset() {
    if (isActive) return;
    _direction = null;
    _files = const <TransferFile>[];
    _progress = TransferProgress.zero;
    _status = TransferStatus.pending;
    _error = null;
    _deviceName = null;
    _startedAt = null;
    _activePeerId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _promptTimer?.cancel();
    _connection.removeListener(_onConnectionChanged);
    for (final _BoundPeer peer in _peers.values) {
      peer.receiver.dispose();
    }
    _peers.clear();
    super.dispose();
  }

  /// Keeps one receiver attached to every connected device, adding and
  /// dropping them as links come and go.
  void _onConnectionChanged() {
    final List<PeerLink> connected = _connection.connectedLinks;
    final Map<String, PeerLink> byId = <String, PeerLink>{
      for (final PeerLink link in connected) link.id: link,
    };

    bool changed = false;

    for (final String id in _peers.keys.toList()) {
      final _BoundPeer bound = _peers[id]!;
      final PeerLink? link = byId[id];
      // A link that reconnected carries a different session, so its receiver
      // is stale even though the row on screen looks unchanged.
      if (link != null && identical(link.session, bound.session)) continue;

      _peers.remove(id);
      bound.receiver.dispose();
      changed = true;
      _onPeerLost(id, bound);
    }

    for (final PeerLink link in connected) {
      final HozaSession? session = link.session;
      if (session == null || _peers.containsKey(link.id)) continue;

      _peers[link.id] = _BoundPeer(
        link: link,
        session: session,
        receiver: TransferReceiver(
          session,
          downloadPath: _settings.downloadPath ?? '',
          confirm: (List<TransferFile> files) => _confirmOffer(link, files),
          onProgress: _onProgress,
          onStarted: (String id, List<TransferFile> files) =>
              _onReceiveStarted(link, files),
          onFinished: _onReceiveFinished,
        ),
      );
      changed = true;
    }

    if (changed) notifyListeners();
  }

  /// A device went away. Anything of its that was still on screen has to be
  /// resolved here, or the user is left watching a progress bar or a prompt
  /// belonging to a connection that no longer exists.
  void _onPeerLost(String id, _BoundPeer bound) {
    if (_offerPeerId == id) {
      _offer?.reject();
      _offerPeerId = null;
    }
    if (_activePeerId != id || !isActive || isSending) return;
    Log.warn('Transfer', 'Lost ${bound.link.name} mid-transfer');
    _activePeerId = null;
    _applyFailure(HozaError.lost);
    _record();
  }

  /// Raises the incoming prompt, or takes the files straight away when the user
  /// has turned auto-accept on.
  Future<bool> _confirmOffer(PeerLink link, List<TransferFile> files) {
    // One transfer at a time. Saying no here is what makes that visible on the
    // other device, instead of its offer sitting unanswered until it times
    // out.
    if (isActive || _offer != null) {
      Log.info(
        'Transfer',
        'Declining ${files.length} file(s) from ${link.name}: already busy',
      );
      return Future<bool>.value(false);
    }

    if (_settings.settings.autoAccept) {
      Log.info('Transfer', 'Auto-accepting ${files.length} file(s)');
      return Future<bool>.value(true);
    }

    final Completer<bool> decision = Completer<bool>();
    final PendingOffer offer = PendingOffer(
      decision,
      files: files,
      deviceName: link.device.name,
    );
    _offer = offer;
    _offerPeerId = link.id;
    notifyListeners();

    if (_settings.settings.notificationsEnabled) {
      unawaited(
        NotificationService.incoming(
          deviceName: offer.deviceName,
          fileCount: files.length,
          totalBytes: offer.totalBytes,
        ),
      );
    }

    _promptTimer?.cancel();
    _promptTimer = Timer(_promptWindow, offer.reject);

    return decision.future.whenComplete(() {
      _promptTimer?.cancel();
      _promptTimer = null;
      // A stale "incoming file" alert must not outlive the prompt it was
      // announcing.
      unawaited(NotificationService.clearIncoming());
      if (!identical(_offer, offer)) return;
      _offer = null;
      _offerPeerId = null;
      notifyListeners();
    });
  }

  void _onProgress(TransferProgress progress) {
    _progress = progress;
    // The first progress tick on the sending side means the offer was accepted
    // and bytes are moving.
    if (_status == TransferStatus.awaitingApproval) {
      _status = TransferStatus.inProgress;
    }
    _publishSessionProgress();
    notifyListeners();
  }

  /// Mirrors the transfer onto the Android session notification.
  ///
  /// The whole point of that notification is the user who is *not* looking at
  /// this screen - they switched away, and it is what keeps the process alive
  /// while they are gone. A bar that never moves would make it look stuck.
  ///
  /// Costs nothing off Android, and nothing on it either unless the whole
  /// percent has changed: [ForegroundService] drops a repeat of what is
  /// already showing, and progress arrives many times a second.
  void _publishSessionProgress() {
    if (!isActive) {
      _connection.updateSessionProgress();
      return;
    }
    final int total = _progress.totalBytes;
    final int? percent = total <= 0
        ? null
        : ((_progress.bytesTransferred * 100) ~/ total).clamp(0, 100);
    final String what = _files.length == 1
        ? _files.first.name
        : '${_files.length} files';
    final String who = _deviceName == null
        ? ''
        : isSending
            ? ' to $_deviceName'
            : ' from $_deviceName';
    _connection.updateSessionProgress(
      text: '${isSending ? 'Sending' : 'Receiving'} $what$who',
      percent: percent,
    );
  }

  void _onReceiveStarted(PeerLink link, List<TransferFile> files) {
    _direction = TransferDirection.receive;
    _files = files;
    _deviceName = link.device.name;
    _activePeerId = link.id;
    _startedAt = DateTime.now();
    _error = null;
    _status = TransferStatus.inProgress;
    _progress = TransferProgress(
      bytesTransferred: 0,
      totalBytes: files.fold<int>(0, (int sum, TransferFile f) => sum + f.size),
      bytesPerSecond: 0,
      filesTotal: files.length,
    );
    notifyListeners();
  }

  void _onReceiveFinished(
    String transferId,
    List<TransferFile> saved,
    HozaError? error,
  ) {
    if (error == null) {
      // Swap in the saved copies, which carry the real on-disk paths.
      if (saved.isNotEmpty) _files = saved;
      _status = TransferStatus.completed;
    } else {
      _applyFailure(error);
    }
    _activePeerId = null;
    _record();
    notifyListeners();
  }

  void _applyFailure(HozaError error) {
    _error = error;
    _status = switch (error.kind) {
      HozaErrorKind.cancelled => TransferStatus.cancelled,
      HozaErrorKind.refused => TransferStatus.rejected,
      _ => TransferStatus.failed,
    };
  }

  /// Writes the finished transfer to history and, if the app is in the
  /// background, posts a notice. Neither is awaited: both are conveniences and
  /// must never hold up the result the user is waiting to see.
  void _record() {
    // The one place both directions pass through when they stop, so it is
    // where the session notification goes back to saying nothing is moving.
    _publishSessionProgress();

    final TransferDirection? direction = _direction;
    if (direction == null || _files.isEmpty) return;

    if (_settings.settings.notificationsEnabled) {
      if (_status == TransferStatus.completed) {
        unawaited(
          NotificationService.completed(
            sent: direction == TransferDirection.send,
            deviceName: _deviceName ?? 'a nearby device',
            fileCount: _files.length,
          ),
        );
      } else if (_status == TransferStatus.failed) {
        unawaited(
          NotificationService.failed(
            reason: _error?.message ?? 'The transfer did not finish.',
          ),
        );
      }
    }

    unawaited(
      _history.add(
        TransferRecord(
          id: Ids.next('h'),
          direction: direction,
          deviceName: _deviceName ?? 'Unknown device',
          files: _files,
          status: _status,
          startedAt: _startedAt ?? DateTime.now(),
          completedAt: DateTime.now(),
          failureReason: _error?.message,
        ),
      ),
    );
  }
}
