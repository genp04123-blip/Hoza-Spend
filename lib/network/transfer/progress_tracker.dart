import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../core/models/transfer.dart';

/// Turns a running byte count into the numbers the transfer screen shows.
///
/// Ticks on a timer rather than on every chunk, for two reasons: a fast
/// transfer would otherwise rebuild the UI thousands of times a second, and a
/// speed measured over one 64 KB chunk is noise, not information.
class ProgressTracker {
  ProgressTracker({
    required this.totalBytes,
    required this.filesTotal,
    required this.onUpdate,
  });

  /// Weight given to the newly measured rate on each tick. Low enough that the
  /// figure stops jittering, high enough that it still reacts when the network
  /// genuinely slows down.
  static const double _smoothing = 0.25;

  final int totalBytes;
  final int filesTotal;
  final void Function(TransferProgress progress) onUpdate;

  int _bytes = 0;
  int _filesDone = 0;
  String? _currentFile;
  double _speed = 0;
  bool _paused = false;

  int _lastBytes = 0;
  DateTime _lastTick = DateTime.now();
  Timer? _timer;

  int get bytes => _bytes;

  void start() {
    _lastTick = DateTime.now();
    _timer ??= Timer.periodic(AppConstants.progressInterval, (_) => _tick());
  }

  void addBytes(int count) => _bytes += count;

  /// Marks the transfer as held, or released.
  ///
  /// A pause is a decision, not a slow network, so the speed and the estimate
  /// go blank instead of decaying towards zero and telling the user their
  /// transfer has hours left. Resuming reseeds the measurement from the
  /// current byte count, so the wait is not averaged into the rate that comes
  /// after it.
  void setPaused(bool paused) {
    if (_paused == paused) return;
    _paused = paused;
    _lastBytes = _bytes;
    _lastTick = DateTime.now();
    if (!paused) _speed = 0;
    onUpdate(snapshot());
  }

  void beginFile(String name) => _currentFile = name;

  void completeFile() => _filesDone++;

  /// Emits one final update and stops. Called on success, failure and cancel
  /// alike, so the last figure the user sees is the true one.
  void stop() {
    _timer?.cancel();
    _timer = null;
    onUpdate(snapshot());
  }

  TransferProgress snapshot() => TransferProgress(
        bytesTransferred: _bytes,
        totalBytes: totalBytes,
        bytesPerSecond: _paused ? 0 : _speed,
        currentFileName: _currentFile,
        filesDone: _filesDone,
        filesTotal: filesTotal,
        isPaused: _paused,
      );

  void _tick() {
    final DateTime now = DateTime.now();
    if (_paused) {
      // The clock keeps moving while nothing arrives. Carrying that interval
      // into the average would show a rate the network never had, so the
      // measurement is simply held alongside the transfer.
      _lastBytes = _bytes;
      _lastTick = now;
      onUpdate(snapshot());
      return;
    }
    final double seconds =
        now.difference(_lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds > 0) {
      final double instant = (_bytes - _lastBytes) / seconds;
      // The first sample seeds the average outright; blending from zero would
      // show a speed far below reality for the first second.
      _speed = _speed == 0
          ? instant
          : _speed * (1 - _smoothing) + instant * _smoothing;
    }
    _lastBytes = _bytes;
    _lastTick = now;
    onUpdate(snapshot());
  }
}
