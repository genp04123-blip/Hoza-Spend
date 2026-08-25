import 'dart:io';

import '../../core/utils/log.dart';

/// What this device can see of the local network.
///
/// Everything here uses `dart:io` only. A connectivity plugin would report
/// whether there is internet, which is the wrong question: HozaSend needs to
/// know whether there is a *local* network, and a hotspot with no internet is a
/// perfectly good one.
class NetworkInfo {
  const NetworkInfo._();

  static const String _tag = 'Network';

  /// Addresses Windows and Android hand out when no DHCP server answered.
  /// A device on one of these has no peers, so it does not count as connected.
  static bool _isLinkLocal(String address) => address.startsWith('169.254.');

  /// Non-loopback IPv4 addresses currently assigned to this device.
  static Future<List<String>> localAddresses() async {
    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      return <String>[
        for (final NetworkInterface interface in interfaces)
          for (final InternetAddress address in interface.addresses)
            address.address,
      ];
    } catch (error) {
      Log.error(_tag, 'Could not list interfaces', error);
      return const <String>[];
    }
  }

  /// True when this device is on a usable local network, internet or not.
  static Future<bool> hasLocalNetwork() async {
    final List<String> addresses = await localAddresses();
    return addresses.any((String address) => !_isLinkLocal(address));
  }

  /// Where discovery beacons are sent.
  ///
  /// Dart does not expose an interface netmask, so the subnet-directed
  /// broadcast is derived by assuming a /24. That holds for ordinary home
  /// Wi-Fi and for every Android hotspot, which is the primary scenario. The
  /// limited broadcast 255.255.255.255 is always included as the fallback for
  /// anything with a different mask.
  ///
  /// Both are link-local by definition: routers do not forward them, so
  /// discovery cannot leak past the network the user is actually on.
  static Future<List<InternetAddress>> broadcastTargets() async {
    final Set<String> targets = <String>{'255.255.255.255'};
    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final NetworkInterface interface in interfaces) {
        for (final InternetAddress address in interface.addresses) {
          if (_isLinkLocal(address.address)) continue;
          final List<String> octets = address.address.split('.');
          if (octets.length != 4) continue;
          targets.add('${octets[0]}.${octets[1]}.${octets[2]}.255');
        }
      }
    } catch (error) {
      Log.error(_tag, 'Could not resolve broadcast targets', error);
    }

    return <InternetAddress>[
      for (final String target in targets)
        if (InternetAddress.tryParse(target) case final InternetAddress parsed)
          parsed,
    ];
  }
}
