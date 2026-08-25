import 'dart:async';
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/models/hoza_device.dart';
import '../../core/utils/log.dart';
import 'discovery_beacon.dart';
import 'network_info.dart';

/// Supplies the current identity. A function rather than a stored value so a
/// rename in Settings takes effect on the very next beacon, with no restart.
typedef SelfDeviceProvider = HozaDevice Function();

/// Finds other HozaSend devices on the local network, and makes this one
/// findable.
///
/// UDP broadcast rather than mDNS: mDNS needs an extra plugin on both
/// platforms, is unreliable on Android hotspots, and buys nothing here. A
/// broadcast beacon is a few dozen bytes every two seconds and works on any
/// subnet, with or without internet.
///
/// This class knows nothing about widgets. It publishes a stream of devices and
/// the UI layer decides what to do with it.
class DiscoveryService {
  DiscoveryService({required this.selfDevice});

  final SelfDeviceProvider selfDevice;

  static const String _tag = 'Discovery';

  /// Beacons between recomputing broadcast targets. Wi-Fi can change under us;
  /// ten seconds is soon enough to notice without re-listing interfaces
  /// constantly.
  static const int _retargetEvery = 5;

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  Timer? _sweepTimer;
  int _ticks = 0;
  List<InternetAddress> _targets = const <InternetAddress>[];

  final Map<String, HozaDevice> _devices = <String, HozaDevice>{};
  final StreamController<List<HozaDevice>> _output =
      StreamController<List<HozaDevice>>.broadcast();

  /// Emits whenever the visible set of devices changes. A beacon that only
  /// refreshes an existing device does not emit, so a steady room full of
  /// devices costs zero rebuilds.
  Stream<List<HozaDevice>> get stream => _output.stream;

  bool get isRunning => _socket != null;

  List<HozaDevice> get devices => _snapshot();

  /// Returns false if the port could not be opened; the caller turns that into
  /// a message the user can act on.
  Future<bool> start() async {
    if (_socket != null) return true;

    try {
      final RawDatagramSocket socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        AppConstants.discoveryPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      socket.listen(_onSocketEvent);
      _socket = socket;
    } on SocketException catch (error) {
      Log.warn(
        _tag,
        'Could not bind UDP ${AppConstants.discoveryPort}: '
        '${error.osError?.message ?? error.message}',
      );
      return false;
    }

    _targets = await NetworkInfo.broadcastTargets();
    Log.info(
      _tag,
      'Listening on ${AppConstants.discoveryPort}, '
      '${_targets.length} broadcast target(s)',
    );

    _announce(BeaconType.hello);
    _beaconTimer = Timer.periodic(AppConstants.beaconInterval, (_) => _tick());
    _sweepTimer = Timer.periodic(const Duration(seconds: 1), (_) => _sweep());
    return true;
  }

  /// Forget everything found so far and announce again immediately. This is
  /// what "Search again" runs.
  Future<void> refresh() async {
    if (_socket == null) return;
    _devices.clear();
    _emit();
    _targets = await NetworkInfo.broadcastTargets();
    _announce(BeaconType.hello);
    Log.info(_tag, 'Rescanning');
  }

  void stop() {
    if (_socket == null) return;
    // Best effort: peers that get this drop us at once instead of waiting out
    // the seven second timeout.
    _announce(BeaconType.goodbye);

    _beaconTimer?.cancel();
    _beaconTimer = null;
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _socket?.close();
    _socket = null;
    _ticks = 0;
    _devices.clear();
    _emit();
    Log.info(_tag, 'Stopped');
  }

  void dispose() {
    stop();
    _output.close();
  }

  Future<void> _tick() async {
    _ticks++;
    if (_ticks % _retargetEvery == 0) {
      _targets = await NetworkInfo.broadcastTargets();
    }
    _announce(BeaconType.hello);
  }

  void _announce(BeaconType type) {
    final RawDatagramSocket? socket = _socket;
    if (socket == null) return;
    final List<int> payload = DiscoveryBeacon.encode(selfDevice(), type);
    for (final InternetAddress target in _targets) {
      try {
        socket.send(payload, target, AppConstants.discoveryPort);
      } on SocketException {
        // One unreachable interface must not stop the others.
      }
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final Datagram? datagram = _socket?.receive();
    if (datagram == null) return;

    final DiscoveryBeacon? beacon = DiscoveryBeacon.decode(
      datagram.data,
      address: datagram.address.address,
      seenAt: DateTime.now(),
    );
    if (beacon == null) return;

    // Our own broadcast comes straight back to us.
    if (beacon.device.id == selfDevice().id) return;

    if (beacon.type == BeaconType.goodbye) {
      final HozaDevice? left = _devices.remove(beacon.device.id);
      if (left != null) {
        Log.info(_tag, 'Device left: ${left.name}');
        _emit();
      }
      return;
    }

    final HozaDevice? existing = _devices[beacon.device.id];
    // Keep whatever connection status we already had; the beacon only carries
    // identity, not session state.
    _devices[beacon.device.id] = existing == null
        ? beacon.device
        : beacon.device.copyWith(status: existing.status);

    if (existing == null) {
      Log.info(
        _tag,
        'Device discovered: ${beacon.device.name} at ${beacon.device.address}',
      );
      _emit();
    } else if (existing.name != beacon.device.name ||
        existing.address != beacon.device.address) {
      _emit();
    }
    // A beacon that only refreshes lastSeen deliberately does not emit.
  }

  void _sweep() {
    final DateTime now = DateTime.now();
    final List<String> expired = <String>[
      for (final MapEntry<String, HozaDevice> entry in _devices.entries)
        if (now.difference(entry.value.lastSeen) > AppConstants.deviceTimeout)
          entry.key,
    ];
    if (expired.isEmpty) return;
    for (final String id in expired) {
      Log.info(_tag, 'Device timed out: ${_devices[id]?.name}');
      _devices.remove(id);
    }
    _emit();
  }

  List<HozaDevice> _snapshot() {
    final List<HozaDevice> list = _devices.values.toList();
    list.sort((HozaDevice a, HozaDevice b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List<HozaDevice>.unmodifiable(list);
  }

  void _emit() {
    if (_output.isClosed) return;
    _output.add(_snapshot());
  }
}
