import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/models/hoza_device.dart';

/// Why a beacon was sent.
enum BeaconType {
  /// "I am here." Repeated every [AppConstants.beaconInterval].
  hello,

  /// "I am leaving." Sent once on shutdown so peers can drop this device
  /// immediately instead of waiting out the timeout.
  goodbye,
}

/// The discovery packet: a short magic prefix followed by compact JSON.
///
/// The prefix means unrelated UDP traffic that happens to land on our port is
/// rejected in one comparison, before any JSON parsing. Everything here runs
/// against arbitrary bytes from the network, so nothing throws - a malformed
/// packet returns null and is dropped.
class DiscoveryBeacon {
  const DiscoveryBeacon({required this.type, required this.device});

  final BeaconType type;
  final HozaDevice device;

  static List<int> encode(HozaDevice device, BeaconType type) {
    final Map<String, Object?> payload = <String, Object?>{
      'v': AppConstants.protocolVersion,
      't': type.name,
      ...device.toBeacon(),
    };
    return utf8.encode('${AppConstants.beaconMagic}${jsonEncode(payload)}');
  }

  static DiscoveryBeacon? decode(
    List<int> data, {
    required String address,
    required DateTime seenAt,
  }) {
    if (data.length <= AppConstants.beaconMagic.length) return null;

    final String text;
    try {
      text = utf8.decode(data);
    } catch (_) {
      return null;
    }
    if (!text.startsWith(AppConstants.beaconMagic)) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(text.substring(AppConstants.beaconMagic.length));
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final Map<String, Object?> payload = decoded;

    // A different wire version is ignored rather than guessed at; the handshake
    // in Section 4 reports the mismatch in a way the user can act on.
    if (payload['v'] != AppConstants.protocolVersion) return null;

    final HozaDevice? device = HozaDevice.fromBeacon(
      payload,
      address: address,
      seenAt: seenAt,
    );
    if (device == null) return null;

    return DiscoveryBeacon(
      type: BeaconType.values.firstWhere(
        (BeaconType type) => type.name == payload['t'],
        orElse: () => BeaconType.hello,
      ),
      device: device,
    );
  }
}
