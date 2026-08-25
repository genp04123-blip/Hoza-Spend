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

  static Future<HozaSession> connect({
    required HozaDevice target,
    required HozaDevice self,
    required String code,
  }) async {
    final int port = target.port == 0 ? AppConstants.transferPort : target.port;
    Log.info(_tag, 'Connecting to ${target.name} at ${target.address}:$port');

    final Socket socket;
    try {
      socket = await Socket.connect(
        target.address,
        port,
        timeout: AppConstants.connectionTimeout,
      );
    } on SocketException catch (error) {
      throw HozaError(
        HozaErrorKind.network,
        HozaError.unreachable.message,
        detail: '${error.message} ${error.osError?.message ?? ''}'.trim(),
      );
    } on TimeoutException {
      throw HozaError.noAnswer;
    }

    socket.setOption(SocketOption.tcpNoDelay, true);

    final HozaSession session = HozaSession(
      socket,
      remote: target,
      code: code,
      isInitiator: true,
    );
    session.send(ControlMessage.hello(self, code));
    return session;
  }
}
