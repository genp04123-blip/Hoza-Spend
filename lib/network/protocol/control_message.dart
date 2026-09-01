import 'dart:convert';
import 'dart:math';

import '../../core/constants/app_constants.dart';
import '../../core/models/hoza_device.dart';
import '../../core/models/transfer.dart';

/// Messages carried on a HozaSession connection.
///
/// One connection carries the whole conversation: pairing, the transfer offer,
/// each file header, and the file bytes in between. A second connection was
/// considered and rejected - it would need its own handshake, its own liveness
/// handling, and a way to tie it back to the right session, for nothing.
enum ControlType {
  /// Initiator to receiver, always first: identity, wire version, session code.
  hello,

  /// Receiver to initiator: request understood, the user is being asked.
  welcome,

  /// Receiver to initiator: the user accepted. The session is now trusted.
  accept,

  /// Receiver to initiator: the user declined, or it timed out.
  reject,

  /// Sender to receiver: here is what I would like to send.
  offer,
  offerAccept,
  offerReject,

  /// Sender to receiver: this file starts now. Its bytes follow as a run of
  /// [chunk] frames, and the file is complete when [fileDone] arrives.
  file,

  /// Sender to receiver: exactly `n` raw bytes follow this line, then the
  /// framing returns to text.
  ///
  /// A file is sent as many of these rather than as one unbroken run of its
  /// whole length, and that is the difference between a protocol that survives
  /// its own heartbeat and one that does not. With a single run there is no
  /// moment in a five gigabyte file at which either side may write a control
  /// line - so a pong, a cancel or a pause written while a file streams lands
  /// *inside the file*. Returning to text between chunks gives every one of
  /// those somewhere safe to go.
  chunk,

  /// Sender to receiver, after the bytes: the checksum of what was just sent.
  /// It arrives as a trailer rather than in the offer so the sender can hash
  /// while streaming instead of reading every file twice.
  fileDone,

  /// Sender to receiver: that was the last file.
  end,

  /// Either side: hold the transfer where it is. The sender stops feeding
  /// bytes at the next chunk boundary; nothing is torn down and no partial
  /// file is discarded.
  pause,

  /// Either side: carry on from where [pause] stopped.
  resume,

  /// Either side: stop the transfer now.
  cancel,

  /// Receiver to sender: how it went.
  result,

  /// Either side, every few seconds. Half-open TCP is otherwise invisible.
  ping,
  pong,

  /// Either side, before an orderly close.
  bye,

  /// Protocol-level refusal: wrong version, already busy.
  error,

  /// Anything unrecognised, including a newer build's message.
  unknown,
}

/// A six digit code shown on both screens so the user can see they are talking
/// to the device they meant. It is a confirmation aid, not a secret: the real
/// protection is that a human has to press Accept.
class SessionCode {
  const SessionCode._();

  static String generate() {
    final Random random = Random.secure();
    return List<int>.generate(6, (_) => random.nextInt(10)).join();
  }
}

class ControlMessage {
  const ControlMessage(this.type, [this.data = const <String, Object?>{}]);

  /// Year 9999, in milliseconds. A modification time beyond this is not a date
  /// the receiving filesystem can hold, so it is dropped rather than clamped.
  static const int _maxTimestampMs = 253402300799000;

  final ControlType type;
  final Map<String, Object?> data;

  factory ControlMessage.hello(HozaDevice self, String code) {
    return ControlMessage(ControlType.hello, <String, Object?>{
      'v': AppConstants.protocolVersion,
      'session': code,
      ...self.toBeacon(),
    });
  }

  factory ControlMessage.welcome(HozaDevice self) {
    return ControlMessage(ControlType.welcome, self.toBeacon());
  }

  static const ControlMessage accept = ControlMessage(ControlType.accept);
  static const ControlMessage ping = ControlMessage(ControlType.ping);
  static const ControlMessage pong = ControlMessage(ControlType.pong);
  static const ControlMessage bye = ControlMessage(ControlType.bye);

  factory ControlMessage.reject(String reason) => ControlMessage(
        ControlType.reject,
        <String, Object?>{'reason': reason},
      );

  factory ControlMessage.error(String code, String message) => ControlMessage(
        ControlType.error,
        <String, Object?>{'code': code, 'message': message},
      );

  factory ControlMessage.offer(String transferId, List<TransferFile> files) {
    return ControlMessage(ControlType.offer, <String, Object?>{
      'transfer': transferId,
      'totalBytes':
          files.fold<int>(0, (int sum, TransferFile f) => sum + f.size),
      'files':
          files.map((TransferFile f) => f.toWire()).toList(growable: false),
    });
  }

  factory ControlMessage.offerAccept(String transferId) => ControlMessage(
        ControlType.offerAccept,
        <String, Object?>{'transfer': transferId},
      );

  factory ControlMessage.offerReject(String transferId, String reason) =>
      ControlMessage(
        ControlType.offerReject,
        <String, Object?>{'transfer': transferId, 'reason': reason},
      );

  factory ControlMessage.fileHeader(TransferFile file) =>
      ControlMessage(ControlType.file, file.toWire());

  /// Announces the [length] raw bytes that follow this line.
  factory ControlMessage.chunk(int length) => ControlMessage(
        ControlType.chunk,
        <String, Object?>{'n': length},
      );

  factory ControlMessage.pause(String transferId) => ControlMessage(
        ControlType.pause,
        <String, Object?>{'transfer': transferId},
      );

  factory ControlMessage.resume(String transferId) => ControlMessage(
        ControlType.resume,
        <String, Object?>{'transfer': transferId},
      );

  factory ControlMessage.fileDone(String fileId, String checksum) =>
      ControlMessage(
        ControlType.fileDone,
        <String, Object?>{'id': fileId, 'sha256': checksum},
      );

  factory ControlMessage.end(String transferId) => ControlMessage(
        ControlType.end,
        <String, Object?>{'transfer': transferId},
      );

  factory ControlMessage.cancel(String transferId, String reason) =>
      ControlMessage(
        ControlType.cancel,
        <String, Object?>{'transfer': transferId, 'reason': reason},
      );

  factory ControlMessage.result(String transferId, {String? failure}) =>
      ControlMessage(ControlType.result, <String, Object?>{
        'transfer': transferId,
        'ok': failure == null,
        'reason': ?failure,
      });

  String? get reason => data['reason'] as String?;
  String? get errorCode => data['code'] as String?;
  String? get transferId => data['transfer'] as String?;
  String? get fileId => data['id'] as String?;
  String? get checksum => data['sha256'] as String?;
  bool get isOk => data['ok'] == true;

  /// How many raw bytes follow a [ControlType.chunk] line.
  ///
  /// Null for anything absent, negative, or larger than a chunk is allowed to
  /// be. This number decides how much the receiver will take on trust from an
  /// open port, so an unusable one is refused here rather than acted on.
  int? get chunkLength {
    final Object? value = data['n'];
    if (value is! int) return null;
    if (value <= 0 || value > AppConstants.maxChunkSize) return null;
    return value;
  }

  /// The six digit code carried by a [ControlType.hello]. Kept under its own
  /// key so it can never be confused with an error's code.
  String? get sessionCode => data['session'] as String?;

  /// Wire version claimed by a [ControlType.hello]. Null if absent.
  int? get protocolVersion => data['v'] as int?;

  /// The file a [ControlType.file] header describes. No source: the bytes are
  /// arriving on the wire, not being read from disk.
  TransferFile? get fileHeaderValue => _fileFrom(data);

  /// The files listed in an offer.
  List<TransferFile> get offeredFiles {
    final Object? raw = data['files'];
    if (raw is! List) return const <TransferFile>[];
    return <TransferFile>[
      for (final Object? item in raw)
        if (item is Map<String, Object?>)
          if (_fileFrom(item) case final TransferFile file) file,
    ];
  }

  static TransferFile? _fileFrom(Map<String, Object?> json) {
    final Object? id = json['id'];
    final Object? name = json['name'];
    final Object? size = json['size'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (size is! int || size < 0) return null;
    return TransferFile(
      id: id,
      name: name,
      size: size,
      kind: FileKind.values.firstWhere(
        (FileKind kind) => kind.name == json['kind'],
        orElse: () => FileKind.other,
      ),
      // Both are optional, and both come from another device. A timestamp
      // outside what DateTime can hold, or a relative path that is not a
      // string, is simply not carried rather than allowed to fail the file.
      modifiedAt: switch (json['mtime']) {
        final int ms when ms > 0 && ms < _maxTimestampMs =>
          DateTime.fromMillisecondsSinceEpoch(ms),
        _ => null,
      },
      relativePath: switch (json['rel']) {
        final String rel when rel.isNotEmpty => rel,
        _ => null,
      },
    );
  }

  /// Reads the sender's identity out of a hello or welcome. [address] comes
  /// from the socket, never from the message, so a device cannot claim to be
  /// somewhere it is not.
  HozaDevice? deviceFrom(String address) => HozaDevice.fromBeacon(
        data,
        address: address,
        seenAt: DateTime.now(),
      );

  List<int> encode() {
    final Map<String, Object?> payload = <String, Object?>{
      't': type.name,
      ...data,
    };
    return utf8.encode('${jsonEncode(payload)}\n');
  }

  /// Never throws: this parses bytes that arrived from an open port.
  static ControlMessage? decode(String line) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final Map<String, Object?> payload = decoded;

    return ControlMessage(
      ControlType.values.firstWhere(
        (ControlType type) => type.name == payload['t'],
        orElse: () => ControlType.unknown,
      ),
      payload,
    );
  }
}
