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

/// One device we can see, and every address it has answered from.
class _Peer {
  _Peer(this.device, String address, DateTime seenAt) {
    addresses[address] = seenAt;
  }

  HozaDevice device;

  /// Address to when a packet last arrived from it. A device on two networks
  /// at once answers from both, and which of them this device can actually
  /// reach is decided here rather than by whichever packet happened to land
  /// last.
  final Map<String, DateTime> addresses = <String, DateTime>{};

  DateTime get lastSeen => addresses.isEmpty
      ? device.lastSeen
      : addresses.values.reduce(
          (DateTime a, DateTime b) => a.isAfter(b) ? a : b,
        );

  /// What the UI compares against to decide whether anything visible changed.
  String get signature =>
      '${device.id}|${device.name}|${device.address}|${device.port}';
}

/// Finds other HozaSend devices on the local network, and makes this one
/// findable.
///
/// Three mechanisms, each covering the others' blind spot:
///
/// 1. **Broadcast beacons.** A short UDP packet every two seconds to the
///    subnet broadcast address. Cheap, and enough on a well-behaved network.
/// 2. **Unicast replies.** Every hello is answered directly, straight back to
///    the sender. This is what makes discovery instant instead of taking up to
///    a beacon interval, and it means a network that carries broadcast in only
///    one direction still works - which covers Windows Firewall dropping
///    inbound UDP and access points that filter broadcast towards clients.
/// 3. **A unicast sweep.** When broadcast reaches nobody at all, every host on
///    the local subnet is greeted directly - the real subnet, read from the
///    interface's own netmask, not an assumed /24. A few hundred small packets,
///    and it finds peers that broadcast alone never could.
///
/// When all three come up empty for long enough, [seemsBlocked] says so. That
/// is not a fourth mechanism but an admission: something on this network is
/// dropping the traffic, and the user is better told than left watching a
/// spinner.
///
/// UDP rather than mDNS: mDNS needs an extra plugin on both platforms, is
/// unreliable on Android hotspots, and buys nothing here.
///
/// This class knows nothing about widgets. It publishes a stream of devices and
/// the UI layer decides what to do with it.
class DiscoveryService {
  DiscoveryService({required this.selfDevice});

  final SelfDeviceProvider selfDevice;

  static const String _tag = 'Discovery';

  /// Beacons between re-reading the interface list. Wi-Fi can change under us;
  /// ten seconds is soon enough to notice without re-listing constantly.
  static const int _retargetEvery = 5;

  /// Beacons between unicast sweeps while nothing has been found. Eight
  /// seconds: long enough not to be a scan, short enough that a user who is
  /// staring at an empty list is not staring for long.
  static const int _sweepEmptyEvery = 4;

  /// Beacons between sweeps once at least one device is visible. Broadcast is
  /// evidently working, so this is only a safety net for a second device that
  /// cannot be heard.
  static const int _sweepFoundEvery = 30;

  /// Sweep packets sent before yielding. A datagram socket's send buffer is
  /// finite, and firing 254 packets without a pause is how the tail of a sweep
  /// gets silently dropped.
  static const int _sweepBatch = 32;
  static const Duration _sweepPause = Duration(milliseconds: 12);

  /// Shortest gap between two unicast replies to the same address. A peer
  /// behaving oddly cannot turn discovery into a packet storm.
  static const Duration _replyThrottle = Duration(milliseconds: 400);

  /// Fruitless sweeps before discovery admits something is blocking it.
  ///
  /// Three, which at the empty-list sweep interval is around half a minute.
  /// Long enough that a second device still being switched on is not called a
  /// firewall; short enough that a user who really is behind one is not left
  /// guessing. Broadcast, unicast reply and a full subnet sweep have all
  /// produced nothing by this point, and the remaining explanations are all
  /// the network's doing rather than the app's.
  static const int _blockedAfterSweeps = 3;

  /// Called when [seemsBlocked] changes. The UI layer turns it into something
  /// the user can act on.
  void Function()? onDiagnostics;

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  Timer? _sweepTimer;
  int _ticks = 0;
  int _ticksSinceSweep = 0;
  bool _sweeping = false;

  int _bareSweeps = 0;
  bool _sweptOnce = false;

  /// True when every mechanism has been tried enough times to conclude that
  /// this network is not carrying HozaSend's traffic.
  ///
  /// Deliberately a suspicion rather than a diagnosis. It cannot tell a
  /// firewall from client isolation from an empty room, and it says so: what
  /// it is actually reporting is that discovery has done everything it can.
  bool get seemsBlocked => _bareSweeps >= _blockedAfterSweeps;

  List<InternetAddress> _targets = const <InternetAddress>[];
  List<LocalAddress> _locals = const <LocalAddress>[];
  String _networkSignature = '';

  final Map<String, _Peer> _peers = <String, _Peer>{};
  final Map<String, DateTime> _lastReply = <String, DateTime>{};

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

    await _retarget();
    Log.info(
      _tag,
      'Listening on ${AppConstants.discoveryPort}, '
      '${_targets.length} broadcast target(s)',
    );

    _announce(BeaconType.hello);
    _beaconTimer = Timer.periodic(AppConstants.beaconInterval, (_) => _tick());
    _sweepTimer = Timer.periodic(const Duration(seconds: 1), (_) => _expire());

    // The first sweep runs immediately rather than on a schedule. It is the
    // one that matters: if broadcast is going to fail on this network, it has
    // already failed by the time the user has read the screen.
    unawaited(_sweep());
    return true;
  }

  /// Announce again immediately and greet the whole subnet. This is what
  /// "Search again" runs.
  ///
  /// Deliberately does not clear the list. Wiping devices that are answering
  /// perfectly well only makes the screen empty for two seconds, and a user
  /// who pressed a button because one device was missing should not lose the
  /// ones that were already there.
  Future<void> refresh() async {
    if (_socket == null) return;
    Log.info(_tag, 'Rescanning');
    _ticksSinceSweep = 0;
    // The user asked again, so the verdict starts again with them. Leaving a
    // blocked warning up through a rescan would say the app had not bothered -
    // and forgetting the last sweep too makes this a genuinely fresh start
    // rather than one that inherits the evidence it just cleared.
    _sweptOnce = false;
    _clearBlocked();
    await _retarget();
    _announce(BeaconType.hello);
    _greetKnownPeers();
    unawaited(_sweep());
  }

  void stop() {
    if (_socket == null) return;
    // Best effort: peers that get this drop us at once instead of waiting out
    // the seven second timeout.
    _announce(BeaconType.goodbye);
    _greetKnownPeers(BeaconType.goodbye);

    _beaconTimer?.cancel();
    _beaconTimer = null;
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _socket?.close();
    _socket = null;
    _ticks = 0;
    _ticksSinceSweep = 0;
    _sweptOnce = false;
    _clearBlocked();
    _peers.clear();
    _lastReply.clear();
    _emit();
    Log.info(_tag, 'Stopped');
  }

  void dispose() {
    stop();
    _output.close();
  }

  // --- Sending -------------------------------------------------------------

  Future<void> _tick() async {
    _ticks++;
    _ticksSinceSweep++;

    if (_ticks % _retargetEvery == 0) await _retarget();

    _announce(BeaconType.hello);
    // Known peers are greeted directly as well as over broadcast. Once two
    // devices have found each other they stay found even if broadcast stops
    // being delivered, which is the difference between a list that holds
    // steady and one that flickers.
    _greetKnownPeers();

    final int interval =
        _peers.isEmpty ? _sweepEmptyEvery : _sweepFoundEvery;
    if (_ticksSinceSweep >= interval) {
      _ticksSinceSweep = 0;
      unawaited(_sweep());
    }
  }

  /// Re-reads the interfaces. If the addresses changed, the network itself
  /// changed - Wi-Fi swapped for a hotspot, or a new lease - and every peer
  /// found on the old one is unreachable, so the list starts again.
  Future<void> _retarget() async {
    _locals = await NetworkInfo.localAddresses();
    _targets = await NetworkInfo.broadcastTargets();

    // Carries each address's prefix length, so a lease that keeps the address
    // but widens the mask still counts as a different network to sweep.
    final String signature = NetworkInfo.signatureOf(_locals);
    if (signature == _networkSignature) return;

    final bool hadPeers = _peers.isNotEmpty;
    _networkSignature = signature;
    _peers.clear();
    _lastReply.clear();
    _ticksSinceSweep = 0;
    // A different network has not been tried yet, whatever the last one did.
    _sweptOnce = false;
    _clearBlocked();
    Log.info(_tag, 'Network changed: ${signature.isEmpty ? 'none' : signature}');
    if (hadPeers) _emit();
    // A new network is exactly when the sweep earns its keep.
    if (_socket != null) unawaited(_sweep());
  }

  void _announce(BeaconType type) {
    final RawDatagramSocket? socket = _socket;
    if (socket == null) return;
    final List<int> payload = DiscoveryBeacon.encode(selfDevice(), type);
    for (final InternetAddress target in _targets) {
      _sendTo(socket, payload, target);
    }
  }

  /// Sends a beacon straight to every address a known peer has answered from.
  void _greetKnownPeers([BeaconType type = BeaconType.hello]) {
    final RawDatagramSocket? socket = _socket;
    if (socket == null || _peers.isEmpty) return;
    final List<int> payload = DiscoveryBeacon.encode(selfDevice(), type);
    for (final _Peer peer in _peers.values) {
      for (final String address in peer.addresses.keys) {
        final InternetAddress? target = InternetAddress.tryParse(address);
        if (target != null) _sendTo(socket, payload, target);
      }
    }
  }

  /// Greets every host on the local subnet directly.
  ///
  /// The fallback for networks that never deliver a broadcast. Whoever is
  /// listening answers with a unicast reply, so discovery completes without
  /// broadcast being involved in either direction. The range comes from the
  /// interface's real netmask, so the far half of a /23 is covered too.
  Future<void> _sweep() async {
    if (_sweeping) return;
    final RawDatagramSocket? socket = _socket;
    if (socket == null) return;

    _sweeping = true;
    try {
      // The verdict on the *previous* sweep, judged here rather than at the
      // end of it so replies have had the whole interval to arrive instead of
      // the few milliseconds it takes to send the last batch.
      if (_sweptOnce) _judgeLastSweep();
      _sweptOnce = true;

      final List<InternetAddress> targets = await NetworkInfo.sweepTargets();
      if (targets.isEmpty) return;

      final List<int> payload =
          DiscoveryBeacon.encode(selfDevice(), BeaconType.hello);
      int sent = 0;
      for (final InternetAddress target in targets) {
        // Discovery may have been stopped while this was paced out.
        if (!identical(_socket, socket)) return;
        _sendTo(socket, payload, target);
        sent++;
        if (sent % _sweepBatch == 0) await Future<void>.delayed(_sweepPause);
      }
      Log.info(_tag, 'Greeted $sent address(es) directly');
    } finally {
      _sweeping = false;
    }
  }

  /// Records whether the sweep before this one reached anybody.
  void _judgeLastSweep() {
    final bool was = seemsBlocked;
    if (_peers.isEmpty) {
      _bareSweeps++;
      if (seemsBlocked && !was) {
        Log.warn(
          _tag,
          'Nothing found after $_bareSweeps full sweeps; '
          'this network appears to be blocking HozaSend',
        );
      }
    } else {
      _bareSweeps = 0;
    }
    if (seemsBlocked != was) onDiagnostics?.call();
  }

  /// Called wherever the question is being asked again from scratch.
  void _clearBlocked() {
    final bool was = seemsBlocked;
    _bareSweeps = 0;
    if (was) onDiagnostics?.call();
  }

  void _sendTo(
    RawDatagramSocket socket,
    List<int> payload,
    InternetAddress target,
  ) {
    try {
      socket.send(payload, target, AppConstants.discoveryPort);
    } on SocketException {
      // One unreachable interface or host must not stop the others.
    }
  }

  // --- Receiving -----------------------------------------------------------

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    // Drained in a loop: several beacons can be queued behind one read event,
    // and leaving them there delays every device behind the first.
    while (true) {
      final Datagram? datagram = _socket?.receive();
      if (datagram == null) return;
      _onDatagram(datagram);
    }
  }

  void _onDatagram(Datagram datagram) {
    final DateTime now = DateTime.now();
    final String from = datagram.address.address;

    final DiscoveryBeacon? beacon = DiscoveryBeacon.decode(
      datagram.data,
      address: from,
      seenAt: now,
    );
    if (beacon == null) return;

    // Our own broadcast comes straight back to us.
    if (beacon.device.id == selfDevice().id) return;

    if (beacon.type == BeaconType.goodbye) {
      final _Peer? left = _peers.remove(beacon.device.id);
      _lastReply.remove(from);
      if (left != null) {
        Log.info(_tag, 'Device left: ${left.device.name}');
        _emit();
      }
      return;
    }

    // Answered before the merge, so the other device hears back in the same
    // millisecond it was heard rather than after our own next beacon.
    if (beacon.type.wantsReply) _reply(datagram.address, now);

    _merge(beacon, from: from, seenAt: now);
  }

  void _reply(InternetAddress to, DateTime now) {
    final RawDatagramSocket? socket = _socket;
    if (socket == null) return;

    final DateTime? last = _lastReply[to.address];
    if (last != null && now.difference(last) < _replyThrottle) return;
    _lastReply[to.address] = now;

    _sendTo(
      socket,
      DiscoveryBeacon.encode(selfDevice(), BeaconType.reply),
      to,
    );
  }

  void _merge(
    DiscoveryBeacon beacon, {
    required String from,
    required DateTime seenAt,
  }) {
    final String id = beacon.device.id;
    final _Peer? existing = _peers[id];

    if (existing == null) {
      final _Peer peer = _Peer(beacon.device, from, seenAt);
      peer.device = _resolve(peer, beacon.device);
      _peers[id] = peer;
      Log.info(_tag, 'Device discovered: ${peer.device.name} at $from');
      // Whatever the previous sweeps suggested, something is getting through.
      _clearBlocked();
      _emit();
      return;
    }

    final String before = existing.signature;
    existing.addresses[from] = seenAt;
    _prune(existing, seenAt);
    // Keep whatever connection status we already had; the beacon only carries
    // identity, not session state.
    existing.device = _resolve(
      existing,
      beacon.device.copyWith(status: existing.device.status),
    );

    // A beacon that only refreshes lastSeen deliberately does not emit.
    if (existing.signature != before) _emit();
  }

  /// Drops addresses a peer has stopped answering from, so a phone that left
  /// one network does not keep offering an address on it forever.
  void _prune(_Peer peer, DateTime now) {
    if (peer.addresses.length < 2) return;
    peer.addresses.removeWhere(
      (String _, DateTime seen) =>
          now.difference(seen) > AppConstants.deviceTimeout,
    );
  }

  /// Decides which of a peer's addresses this device should actually use.
  ///
  /// Same subnet wins: an address inside a subnet this device is itself on
  /// needs no router, which is the only thing that can be relied on across a
  /// hotspot. Freshness breaks the tie.
  HozaDevice _resolve(_Peer peer, HozaDevice device) {
    final List<MapEntry<String, DateTime>> ranked =
        peer.addresses.entries.toList()
          ..sort((MapEntry<String, DateTime> a, MapEntry<String, DateTime> b) {
            final bool localA = _isReachable(a.key);
            final bool localB = _isReachable(b.key);
            if (localA != localB) return localA ? -1 : 1;
            return b.value.compareTo(a.value);
          });

    if (ranked.isEmpty) return device;
    return device.copyWith(
      address: ranked.first.key,
      lastSeen: peer.lastSeen,
      alternateAddresses: <String>[
        for (final MapEntry<String, DateTime> entry in ranked.skip(1)) entry.key,
      ],
    );
  }

  /// Each interface answers for its own subnet, using the mask the operating
  /// system reported for it rather than an assumed /24. On a /23 that is what
  /// stops a peer in the upper half being ranked as though it were a router
  /// hop away.
  bool _isReachable(String address) =>
      _locals.any((LocalAddress local) => local.contains(address));

  void _expire() {
    final DateTime now = DateTime.now();
    final List<String> expired = <String>[
      for (final MapEntry<String, _Peer> entry in _peers.entries)
        if (now.difference(entry.value.lastSeen) > AppConstants.deviceTimeout)
          entry.key,
    ];
    if (expired.isEmpty) return;
    for (final String id in expired) {
      Log.info(_tag, 'Device timed out: ${_peers[id]?.device.name}');
      _peers.remove(id);
    }
    _emit();
  }

  List<HozaDevice> _snapshot() {
    final List<HozaDevice> list = <HozaDevice>[
      for (final _Peer peer in _peers.values) peer.device,
    ];
    list.sort((HozaDevice a, HozaDevice b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List<HozaDevice>.unmodifiable(list);
  }

  void _emit() {
    if (_output.isClosed) return;
    _output.add(_snapshot());
  }
}
