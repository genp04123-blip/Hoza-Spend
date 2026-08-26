import 'dart:async';
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/errors/hoza_error.dart';
import '../../core/models/hoza_device.dart';
import '../../core/utils/log.dart';
import '../protocol/control_message.dart';
import 'hoza_session.dart';

/// Opens a control connection to a device found by discovery.
///
/// Returns as soon as the socket is up and the hello is on the wire. Waiting
/// for the other user to accept is the caller's job, because that wait needs a
/// visible, cancellable UI rather than a blocked future.
class ConnectionClient {
  const ConnectionClient._();

  static const String _tag = 'Connection';

  /// How long one address gets before the next one is tried.
  ///
  /// Short on purpose. A device on the same subnet answers in milliseconds;
  /// anything that takes seconds is a stale address or a firewall, and the
  /// time is better spent on the next candidate than on waiting out a full
  /// TCP timeout on the first.
  static const Duration _attemptTimeout = Duration(seconds: 4);

  static Future<HozaSession> connect({
    required HozaDevice target,
    required HozaDevice self,
    required String code,
  }) async {
    final int port = target.port == 0 ? AppConstants.transferPort : target.port;
    final List<String> candidates = target.candidateAddresses;

    // The whole attempt is bounded, not each try. A device with three
    // addresses must not take three times as long to give up as one with a
    // single address.
    final DateTime deadline =
        DateTime.now().add(AppConstants.connectionTimeout);

    Object? lastError;
    bool timedOut = false;

    // Two passes over the candidates. Wi-Fi on a phone that has just woken up
    // will refuse the first connection and accept the second a moment later,
    // and asking the user to press the button again for that is a bug they
    // experience as "it only works sometimes".
    for (int round = 0; round < 2; round++) {
      for (final String address in candidates) {
        final Duration remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          return _giveUp(target, lastError, timedOut);
        }

        final Duration budget =
            remaining < _attemptTimeout ? remaining : _attemptTimeout;
        Log.info(_tag, 'Connecting to ${target.name} at $address:$port');

        try {
          final Socket socket =
              await Socket.connect(address, port, timeout: budget);
          socket.setOption(SocketOption.tcpNoDelay, true);

          // The address that answered is the one this session is on, whatever
          // discovery listed first.
          final HozaSession session = HozaSession(
            socket,
            remote: target.copyWith(address: address),
            code: code,
            isInitiator: true,
          );
          session.send(ControlMessage.hello(self, code));
          return session;
        } on SocketException catch (error) {
          lastError = error;
        } on TimeoutException {
          timedOut = true;
        }
      }
    }

    return _giveUp(target, lastError, timedOut);
  }

  /// Turns whatever went wrong into the one sentence the user needs.
  static Never _giveUp(HozaDevice target, Object? lastError, bool timedOut) {
    Log.warn(_tag, 'Could not reach ${target.name} on any known address');
    if (timedOut && lastError == null) throw HozaError.noAnswer;
    final SocketException? socketError =
        lastError is SocketException ? lastError : null;
    throw HozaError(
      HozaErrorKind.network,
      HozaError.unreachable.message,
      detail: socketError == null
          ? null
          : '${socketError.message} '
              '${socketError.osError?.message ?? ''}'.trim(),
    );
  }
}
