import 'dart:async';
import 'dart:io';

/// What went wrong, in terms the UI can branch on.
enum HozaErrorKind {
  /// Could not reach the other device at all.
  network,

  /// The other device answered but said no.
  refused,

  /// Nobody answered in time.
  timeout,

  /// The other device runs an incompatible build.
  versionMismatch,

  /// The other device is already in a session.
  busy,

  /// This user stopped it.
  cancelled,

  /// Reading or writing a file failed.
  storage,

  unknown,
}

/// An error with two faces: [message] is written for a user and is the only
/// part ever rendered, while [detail] carries the technical cause and only ever
/// reaches the debug log.
///
/// The guide is explicit that a user must never see "SocketException:
/// Connection reset by peer", so raw exceptions are converted here at the
/// boundary rather than being formatted at each call site.
class HozaError implements Exception {
  const HozaError(this.kind, this.message, {this.detail});

  final HozaErrorKind kind;
  final String message;
  final String? detail;

  static const HozaError unreachable = HozaError(
    HozaErrorKind.network,
    "Couldn't connect.\nMake sure both devices are connected to the same "
        'Wi-Fi or hotspot.',
  );

  static const HozaError lost = HozaError(
    HozaErrorKind.network,
    'Connection lost.\nThe other device may have disconnected.',
  );

  static const HozaError noAnswer = HozaError(
    HozaErrorKind.timeout,
    "The other device didn't answer.\nIt may have gone offline or closed "
        'HozaSend.',
  );

  static const HozaError declined = HozaError(
    HozaErrorKind.refused,
    'Transfer declined.',
  );

  static const HozaError incompatible = HozaError(
    HozaErrorKind.versionMismatch,
    'That device is running a different version of HozaSend.\nUpdate both '
        'devices to continue.',
  );

  static const HozaError deviceBusy = HozaError(
    HozaErrorKind.busy,
    'That device is busy with another transfer.\nTry again in a moment.',
  );

  static const HozaError cancelled = HozaError(
    HozaErrorKind.cancelled,
    'Cancelled.',
  );

  /// Converts anything thrown by the network or file layers into something
  /// safe to show. The original is kept in [detail] for the log.
  static HozaError from(Object error) {
    if (error is HozaError) return error;
    if (error is TimeoutException) return noAnswer;
    if (error is FileSystemException) {
      return HozaError(
        HozaErrorKind.storage,
        "Couldn't save the file.\nCheck there is enough space, or choose "
            'another location.',
        detail: error.toString(),
      );
    }
    if (error is SocketException) {
      return HozaError(
        HozaErrorKind.network,
        unreachable.message,
        detail: '${error.message} ${error.osError?.message ?? ''}'.trim(),
      );
    }
    return HozaError(
      HozaErrorKind.unknown,
      'Something went wrong.\nPlease try again.',
      detail: error.toString(),
    );
  }

  @override
  String toString() => 'HozaError(${kind.name}): ${detail ?? message}';
}
