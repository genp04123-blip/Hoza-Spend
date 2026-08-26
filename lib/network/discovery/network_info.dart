import 'dart:io';

import '../../core/utils/log.dart';
import 'interface_table.dart';

/// Turning an IPv4 address into arithmetic and back.
///
/// Subnets are bit maths, and doing that maths on four decimal strings is how
/// a /23 gets treated as a /24. Everything here works on the 32-bit value.
class Ipv4 {
  const Ipv4._();

  /// The address as a 32-bit integer, or null if it is not four octets.
  static int? parse(String address) {
    final List<String> parts = address.split('.');
    if (parts.length != 4) return null;
    int value = 0;
    for (final String part in parts) {
      final int? octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return null;
      value = (value << 8) | octet;
    }
    return value;
  }

  static String format(int value) {
    return '${(value >> 24) & 0xFF}.${(value >> 16) & 0xFF}.'
        '${(value >> 8) & 0xFF}.${value & 0xFF}';
  }

  /// The mask for a prefix length: /24 is 0xFFFFFF00.
  ///
  /// A /0 is special-cased because shifting a 32-bit quantity by 32 is not
  /// defined the same way everywhere, and Dart's integers are 64-bit besides.
  static int mask(int prefixLength) {
    if (prefixLength <= 0) return 0;
    if (prefixLength >= 32) return 0xFFFFFFFF;
    return (0xFFFFFFFF << (32 - prefixLength)) & 0xFFFFFFFF;
  }
}

/// One IPv4 address currently assigned to this device, and the subnet it is
/// on.
///
/// Carries the interface it came from, because "which network is this" is the
/// question discovery keeps having to answer: a phone can be on Wi-Fi and
/// running a hotspot and holding a cellular address all at once, and only two
/// of those three can reach a peer.
class LocalAddress {
  const LocalAddress({
    required this.address,
    required this.interfaceName,
    this.prefixLength = defaultPrefixLength,
  });

  /// What to assume when the operating system will not say.
  ///
  /// Every home router and every Android hotspot hands out a /24, so this is
  /// right far more often than not - but it is the fallback, not the rule.
  /// [InterfaceTable] asks the OS for the real mask first.
  static const int defaultPrefixLength = 24;

  final String address;
  final String interfaceName;

  /// Bits of network in this address's mask. 24 for a typical 255.255.255.0.
  final int prefixLength;

  /// The first three octets - "192.168.43".
  ///
  /// A label, not a subnet: it is what a person recognises an address by, and
  /// it is what the fallback uses when the real mask is unknown. Anything that
  /// has to be *correct* about the subnet uses [network] or [contains].
  String get prefix {
    final int cut = address.lastIndexOf('.');
    return cut < 0 ? address : address.substring(0, cut);
  }

  int? get _value => Ipv4.parse(address);

  /// The subnet's base address, as an integer.
  int? get network {
    final int? value = _value;
    return value == null ? null : value & Ipv4.mask(prefixLength);
  }

  /// The subnet-directed broadcast for this address.
  ///
  /// On a /24 that is the familiar x.y.z.255. On a /23 based at 10.1.0.0 it is
  /// 10.1.1.255, which is exactly the address the old /24 guess got wrong: it
  /// would send to 10.1.0.255, an ordinary host that may not even exist.
  String get broadcast {
    final int? base = network;
    if (base == null || prefixLength >= 31) return '255.255.255.255';
    return Ipv4.format(base | (~Ipv4.mask(prefixLength) & 0xFFFFFFFF));
  }

  /// True when [other] is on this same subnet, and therefore reachable without
  /// a router in between.
  bool contains(String other) {
    final int? base = network;
    final int? value = Ipv4.parse(other);
    if (base == null || value == null) return false;
    return (value & Ipv4.mask(prefixLength)) == base;
  }

  /// Usable host addresses in this subnet. Zero for a /31 or /32, which are
  /// point-to-point links with no room for a peer to be found on.
  int get hostCount {
    if (prefixLength >= 31) return 0;
    return (1 << (32 - prefixLength)) - 2;
  }

  @override
  String toString() => '$address/$prefixLength ($interfaceName)';
}

/// What this device can see of the local network.
///
/// Addresses and interface names come from `dart:io`; the netmask that goes
/// with each one comes from [InterfaceTable], which asks the operating system
/// directly. A connectivity plugin would report whether there is internet,
/// which is the wrong question: HozaSend needs to know whether there is a
/// *local* network, and a hotspot with no internet is a perfectly good one.
class NetworkInfo {
  const NetworkInfo._();

  static const String _tag = 'Network';

  /// The most addresses one sweep will greet, across all subnets together.
  ///
  /// A /24 has 254 hosts and fits comfortably. A /22 has 1022 and does not:
  /// greeting all of them is four times the traffic for a room that almost
  /// certainly has both devices in the same corner of the range. The cap is
  /// spent on the addresses nearest this device's own, and what it leaves out
  /// is logged rather than silently dropped.
  static const int maxSweepHosts = 512;

  /// Interfaces that can never carry a HozaSend peer, matched as a lowercase
  /// substring of the interface name.
  ///
  /// Two kinds, for two different reasons. Cellular interfaces, because a
  /// phone on mobile data holds a routable address that no peer in the room
  /// shares - sweeping it would put hundreds of packets on a metered link for
  /// nothing. Virtual adapters, because a Windows machine with Hyper-V,
  /// VirtualBox, WSL or a VPN installed carries several subnets that exist
  /// only inside that one machine.
  ///
  /// Wi-Fi and hotspot interfaces are deliberately absent: `wlan0`, `ap0`,
  /// `swlan0`, `wlan1`, `en0`, `Wi-Fi` and `Ethernet` all pass.
  static const List<String> _ignoredInterfaces = <String>[
    // Cellular.
    'rmnet', 'ccmni', 'pdp_ip', 'clat', 'seth_', 'v4-rmnet',
    // Virtual machine, container and VPN adapters.
    'vethernet', 'virtualbox', 'vmware', 'vmnet', 'hyper-v', 'docker',
    'veth', 'utun', 'tun', 'tap', 'zerotier', 'hamachi', 'tailscale',
    'wireguard', 'wg0', 'ppp', 'teredo', 'isatap', 'loopback',
    // Link-layer oddities that hold an address but reach nothing useful.
    'bluetooth', 'dummy', 'awdl', 'llw',
  ];

  /// Addresses Windows and Android hand out when no DHCP server answered.
  /// A device on one of these has no peers, so it does not count as connected.
  static bool _isLinkLocal(String address) => address.startsWith('169.254.');

  static bool _isIgnored(String interfaceName) {
    final String name = interfaceName.toLowerCase();
    return _ignoredInterfaces.any(name.contains);
  }

  /// True for the three ranges RFC 1918 reserves for private use.
  ///
  /// Only ever used to gate the unicast sweep, never to decide whether the
  /// device is online: a few campus and office networks really do hand out
  /// public addresses internally, and refusing to run there would break a
  /// setup that works today.
  static bool isPrivate(String address) {
    final List<String> octets = address.split('.');
    if (octets.length != 4) return false;
    final int? first = int.tryParse(octets[0]);
    final int? second = int.tryParse(octets[1]);
    if (first == null || second == null) return false;
    if (first == 10) return true;
    if (first == 172 && second >= 16 && second <= 31) return true;
    if (first == 192 && second == 168) return true;
    return false;
  }

  /// True when [a] and [b] sit in the same subnet of [prefixLength] bits.
  ///
  /// Defaults to a /24 because that is the answer when nothing better is
  /// known. Where the real mask *is* known, use [LocalAddress.contains]
  /// instead - it carries the interface's own prefix length rather than this
  /// assumption.
  static bool sameSubnet(
    String a,
    String b, {
    int prefixLength = LocalAddress.defaultPrefixLength,
  }) {
    final int? left = Ipv4.parse(a);
    final int? right = Ipv4.parse(b);
    if (left == null || right == null) return false;
    final int mask = Ipv4.mask(prefixLength);
    return (left & mask) == (right & mask);
  }

  /// Every usable IPv4 address this device holds, with its real subnet mask,
  /// cellular and virtual adapters excluded.
  ///
  /// Falls back to the unfiltered list if filtering left nothing: an unusual
  /// interface name must not be the reason a device believes it is offline.
  static Future<List<LocalAddress>> localAddresses() async {
    final List<LocalAddress> all = <LocalAddress>[];
    final List<LocalAddress> usable = <LocalAddress>[];

    // Read once for the whole pass rather than per address: one syscall for
    // the machine, not one per interface.
    final Map<String, int> prefixes = InterfaceTable.prefixLengths();

    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final NetworkInterface interface in interfaces) {
        final bool ignored = _isIgnored(interface.name);
        for (final InternetAddress address in interface.addresses) {
          if (_isLinkLocal(address.address)) continue;
          final LocalAddress local = LocalAddress(
            address: address.address,
            interfaceName: interface.name,
            prefixLength: prefixes[address.address] ??
                LocalAddress.defaultPrefixLength,
          );
          all.add(local);
          if (!ignored) usable.add(local);
        }
      }
    } catch (error) {
      Log.error(_tag, 'Could not list interfaces', error);
      return const <LocalAddress>[];
    }

    return usable.isEmpty ? all : usable;
  }

  /// True when this device is on a usable local network, internet or not.
  static Future<bool> hasLocalNetwork() async {
    final List<LocalAddress> addresses = await localAddresses();
    return addresses.isNotEmpty;
  }

  /// A short string that changes whenever the set of local addresses does.
  ///
  /// Discovery compares it between ticks: switching from Wi-Fi to a hotspot,
  /// or picking up a new DHCP lease, changes every peer's reachability, and
  /// waiting out a timer to notice is how a device sits in an empty list while
  /// the other one is two feet away. The prefix length is part of it, because
  /// a lease that keeps the address and widens the mask is still a different
  /// network to sweep.
  static Future<String> signature() async {
    return signatureOf(await localAddresses());
  }

  /// The signature of an address list already in hand.
  static String signatureOf(List<LocalAddress> addresses) {
    final List<String> values = <String>[
      for (final LocalAddress local in addresses)
        '${local.address}/${local.prefixLength}',
    ]..sort();
    return values.join(',');
  }

  /// Where discovery beacons are broadcast.
  ///
  /// The subnet-directed address is computed from the interface's real mask,
  /// so a /23 or a /22 gets the address its own hosts actually listen on
  /// rather than the x.y.z.255 a /24 assumption would produce. The limited
  /// broadcast 255.255.255.255 is always included last as the fallback.
  ///
  /// Both are link-local by definition: routers do not forward them, so
  /// discovery cannot leak past the network the user is actually on.
  ///
  /// The subnet-directed form matters more than it looks on Android. A phone
  /// joined to a hotspot with no internet keeps mobile data as its default
  /// route, so anything sent to 255.255.255.255 leaves over cellular and
  /// reaches nobody; 192.168.43.255 matches the Wi-Fi subnet's own route and
  /// goes out of the right interface.
  static Future<List<InternetAddress>> broadcastTargets() async {
    final Set<String> targets = <String>{};
    for (final LocalAddress local in await localAddresses()) {
      targets.add(local.broadcast);
    }
    // Last, so the interface-specific ones are tried first.
    targets.add('255.255.255.255');

    return <InternetAddress>[
      for (final String target in targets)
        if (InternetAddress.tryParse(target) case final InternetAddress parsed)
          parsed,
    ];
  }

  /// Every host address worth greeting directly, nearest this device first.
  ///
  /// This is the fallback for networks where broadcast never arrives -
  /// Windows Firewall dropping inbound UDP, a router with broadcast filtering,
  /// an access point isolating clients from each other. Unicast still works on
  /// most of them, so walking the subnet finds peers that broadcast alone
  /// never would.
  ///
  /// The range comes from the interface's real mask, so the far half of a /23
  /// is no longer invisible. Where the subnet is larger than [maxSweepHosts],
  /// addresses are taken outward from this device's own - DHCP hands
  /// neighbouring leases to devices that arrive together, so the addresses
  /// next to ours are where a peer in the same room is most likely to be.
  ///
  /// Restricted to RFC 1918 subnets. A public range here would mean either a
  /// cellular link that slipped past the interface filter or a corporate
  /// network where greeting hundreds of addresses is not this app's business.
  static Future<List<InternetAddress>> sweepTargets() async {
    final List<LocalAddress> locals = await localAddresses();
    final Set<String> own = <String>{
      for (final LocalAddress local in locals) local.address,
    };

    // One sweep per distinct subnet, however many addresses this device holds
    // on it.
    final Map<int, LocalAddress> subnets = <int, LocalAddress>{};
    for (final LocalAddress local in locals) {
      if (!isPrivate(local.address)) continue;
      final int? base = local.network;
      if (base == null || local.hostCount <= 0) continue;
      subnets.putIfAbsent(base, () => local);
    }
    if (subnets.isEmpty) return const <InternetAddress>[];

    final int budget = maxSweepHosts ~/ subnets.length;
    final List<InternetAddress> targets = <InternetAddress>[];
    int skipped = 0;

    for (final LocalAddress local in subnets.values) {
      final int base = local.network!;
      final int broadcast = base | (~Ipv4.mask(local.prefixLength) & 0xFFFFFFFF);
      final int self = Ipv4.parse(local.address)!;

      int taken = 0;
      // Outward from this device's own address in both directions at once, so
      // a capped sweep covers the neighbourhood rather than the bottom of the
      // range.
      for (int step = 1; taken < budget; step++) {
        final int below = self - step;
        final int above = self + step;
        final bool hasBelow = below > base;
        final bool hasAbove = above < broadcast;
        if (!hasBelow && !hasAbove) break;

        for (final int candidate in <int>[
          if (hasBelow) below,
          if (hasAbove) above,
        ]) {
          if (taken >= budget) break;
          final String address = Ipv4.format(candidate);
          if (own.contains(address)) continue;
          final InternetAddress? parsed = InternetAddress.tryParse(address);
          if (parsed == null) continue;
          targets.add(parsed);
          taken++;
        }
      }

      final int reachable = local.hostCount - 1;
      if (taken < reachable) skipped += reachable - taken;
    }

    if (skipped > 0) {
      // Said out loud rather than swallowed: a sweep that covered part of the
      // subnet is a different fact to one that covered all of it, and it is
      // the explanation if a peer at the far end is never found.
      Log.info(
        _tag,
        'Sweep covers ${targets.length} address(es); '
        '$skipped further out not greeted',
      );
    }
    return targets;
  }
}
