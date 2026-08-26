/// The platform a device reports in its discovery beacon.
enum DevicePlatform {
  android,
  windows,
  ios,
  macos,
  linux,
  unknown;

  static DevicePlatform fromWire(String? value) {
    return DevicePlatform.values.firstWhere(
      (DevicePlatform p) => p.name == value,
      orElse: () => DevicePlatform.unknown,
    );
  }

  String get label => switch (this) {
        DevicePlatform.android => 'Android',
        DevicePlatform.windows => 'Windows',
        DevicePlatform.ios => 'iPhone',
        DevicePlatform.macos => 'Mac',
        DevicePlatform.linux => 'Linux',
        DevicePlatform.unknown => 'Device',
      };

  /// True for platforms that get the desktop layout and mouse affordances.
  bool get isDesktop =>
      this == DevicePlatform.windows ||
      this == DevicePlatform.macos ||
      this == DevicePlatform.linux;
}

/// What we currently know about a device we can see on the network.
enum DeviceStatus { available, connecting, connected, busy, unavailable }

/// A HozaSend device discovered on the local network.
///
/// Built from a UDP beacon, so every field here survives a JSON round trip.
/// [address] and [lastSeen] are local observations, not beacon content.
class HozaDevice {
  const HozaDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.address,
    required this.port,
    required this.appVersion,
    required this.lastSeen,
    this.status = DeviceStatus.available,
    this.alternateAddresses = const <String>[],
  });

  /// Stable per-installation id. Survives renames, so one device is not listed
  /// twice after the user changes its name.
  final String id;

  final String name;
  final DevicePlatform platform;

  /// IP address the beacon arrived from.
  final String address;

  /// TCP port this device listens on for transfers.
  final int port;

  final String appVersion;

  /// When the last beacon arrived. Drives expiry from the device list.
  final DateTime lastSeen;

  final DeviceStatus status;

  /// Other addresses this same device has answered from, most recent first.
  ///
  /// A device can hold several at once - a laptop on Ethernet and Wi-Fi, a
  /// phone joined to Wi-Fi while running a hotspot - and only some of them
  /// are reachable from here. Discovery picks the best one for [address] and
  /// keeps the rest, so a connection that fails on the first has somewhere
  /// else to go instead of failing outright.
  final List<String> alternateAddresses;

  /// Every address worth trying, best first and without duplicates.
  List<String> get candidateAddresses => <String>[
        address,
        for (final String other in alternateAddresses)
          if (other != address) other,
      ];

  /// Beacon payload. Deliberately small; it goes out every two seconds.
  Map<String, Object?> toBeacon() => <String, Object?>{
        'id': id,
        'name': name,
        'platform': platform.name,
        'port': port,
        'version': appVersion,
      };

  /// Returns null for a malformed beacon rather than throwing, because this
  /// runs against whatever arrives on an open UDP port.
  static HozaDevice? fromBeacon(
    Map<String, Object?> json, {
    required String address,
    required DateTime seenAt,
  }) {
    final Object? id = json['id'];
    final Object? name = json['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    final Object? port = json['port'];
    return HozaDevice(
      id: id,
      name: name,
      platform: DevicePlatform.fromWire(json['platform'] as String?),
      address: address,
      port: port is int ? port : 0,
      appVersion: json['version'] as String? ?? '',
      lastSeen: seenAt,
    );
  }

  HozaDevice copyWith({
    String? name,
    String? address,
    int? port,
    DateTime? lastSeen,
    DeviceStatus? status,
    List<String>? alternateAddresses,
  }) {
    return HozaDevice(
      id: id,
      name: name ?? this.name,
      platform: platform,
      address: address ?? this.address,
      port: port ?? this.port,
      appVersion: appVersion,
      lastSeen: lastSeen ?? this.lastSeen,
      status: status ?? this.status,
      alternateAddresses: alternateAddresses ?? this.alternateAddresses,
    );
  }

  @override
  bool operator ==(Object other) => other is HozaDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
