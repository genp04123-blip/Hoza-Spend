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

/// The UI-facing half of transferring.
///
/// Holds one transfer at a time, in either direction. A receiver is attached to
/// the session as soon as one exists, because an incoming transfer can start
/// without this user doing anything.
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

  HozaSession? _boundSession;
  TransferSender? _sender;
  TransferReceiver? _receiver;
  PendingOffer? _offer;
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

  /// Sends [files] over the live session. Returns when the transfer has
  /// finished, one way or another.
  Future<void> send(List<TransferFile> files) async {
    final HozaSession? session = _connection.session;
    if (session == null || files.isEmpty || isActive) return;

    _lastSent = List<TransferFile>.unmodifiable(files);
    _direction = TransferDirection.send;
    _files = _lastSent;
    _deviceName = _connection.peer?.name;
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
    _receiver?.cancel();
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
    notifyListeners();
  }

  @override
  void dispose() {
    _promptTimer?.cancel();
    _connection.removeListener(_onConnectionChanged);
    _receiver?.dispose();
    super.dispose();
  }

  void _onConnectionChanged() {
    final HozaSession? session = _connection.session;
    if (identical(session, _boundSession)) return;

    _receiver?.dispose();
    _receiver = null;
    // A prompt for a session that no longer exists has nothing to answer.
    _offer?.reject();
    _boundSession = session;
    if (session == null) {
      notifyListeners();
      return;
    }

    _receiver = TransferReceiver(
      session,
      downloadPath: _settings.downloadPath ?? '',
      confirm: _confirmOffer,
      onProgress: _onProgress,
      onStarted: _onReceiveStarted,
      onFinished: _onReceiveFinished,
    );
  }

  /// Raises the incoming prompt, or takes the files straight away when the user
  /// has turned auto-accept on.
  Future<bool> _confirmOffer(List<TransferFile> files) {
    if (_settings.settings.autoAccept) {
      Log.info('Transfer', 'Auto-accepting ${files.length} file(s)');
      return Future<bool>.value(true);
    }

    final Completer<bool> decision = Completer<bool>();
    final PendingOffer offer = PendingOffer(
      decision,
      files: files,
      deviceName: _connection.peer?.name ?? 'A nearby device',
    );
    _offer = offer;
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
    notifyListeners();
  }

  void _onReceiveStarted(String transferId, List<TransferFile> files) {
    _direction = TransferDirection.receive;
    _files = files;
    _deviceName = _connection.peer?.name;
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
